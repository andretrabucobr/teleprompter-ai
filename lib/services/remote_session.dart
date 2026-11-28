import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// MVP para Wi-Fi local confiável. NÃO criptografa o tráfego WebSocket.
/// A publicação requer revisão de segurança e um canal autenticado/criptografado.
const remoteProtocolVersion = 1;

typedef RemoteCommandHandler = Future<void> Function(String command, dynamic value);

class PairingInfo {
  const PairingInfo(this.host, this.port, this.pin);
  final String host;
  final int port;
  final String pin;

  String get qrData => Uri(
        scheme: 'teleprompter-ai',
        host: 'parear',
        queryParameters: {'host': host, 'port': '$port', 'pin': pin},
      ).toString();

  static PairingInfo? parse(String data) {
    final uri = Uri.tryParse(data);
    if (uri == null || uri.scheme != 'teleprompter-ai' || uri.host != 'parear') {
      return null;
    }
    final host = uri.queryParameters['host'];
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    final pin = uri.queryParameters['pin'];
    if (host == null || port == null || pin == null) return null;
    return validate(host, port, pin);
  }

  static PairingInfo? validate(String host, int port, String pin) {
    final address = InternetAddress.tryParse(host.trim());
    if (address == null || address.type != InternetAddressType.IPv4) return null;
    if (port < 1 || port > 65535 || !RegExp(r'^\d{6}$').hasMatch(pin)) return null;
    return PairingInfo(address.address, port, pin);
  }
}

class RemoteHost {
  RemoteHost({required this.onCommand, required this.currentState, this.onConnection});
  final RemoteCommandHandler onCommand;
  final Map<String, dynamic> Function() currentState;
  final void Function(bool paired)? onConnection;

  HttpServer? _server;
  WebSocket? _controller;
  String? _pin;
  String? _localIp;
  int _invalidAttempts = 0;

  bool get isRunning => _server != null;
  bool get hasController => _controller != null;
  PairingInfo? get pairing => _server == null || _pin == null || _localIp == null
      ? null
      : PairingInfo(_localIp!, _server!.port, _pin!);

  Future<PairingInfo> start() async {
    if (pairing != null) return pairing!;
    final ip = await _findLocalIpv4();
    if (ip == null) throw StateError('Conecte o aparelho a uma rede Wi-Fi local.');
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _localIp = ip;
    _pin = (100000 + Random.secure().nextInt(900000)).toString();
    _invalidAttempts = 0;
    _server!.listen((request) async {
      if (request.uri.path != '/remote') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _listen(socket);
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        } catch (_) { /* a negociação pode ter encerrado a resposta */ }
      }
    });
    return pairing!;
  }

  static Future<String?> _findLocalIpv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final ips = [for (final nic in interfaces) ...nic.addresses.map((a) => a.address)]
        .where((ip) => !ip.startsWith('169.254.'))
        .toList();
    if (ips.isEmpty) return null;
    for (final ip in ips) {
      if (ip.startsWith('192.168.') || ip.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(ip)) {
        return ip;
      }
    }
    return ips.first;
  }

  void _send(WebSocket socket, Map<String, dynamic> data) {
    try {
      socket.add(jsonEncode({'v': remoteProtocolVersion, ...data}));
    } catch (_) { /* conexão interrompida */ }
  }

  void _listen(WebSocket socket) {
    var authorized = false;
    final processed = <int>{};
    var commandQueue = Future<void>.value();
    socket.pingInterval = const Duration(seconds: 15);
    socket.listen((data) async {
      if (data is! String || data.length > 8192) {
        await socket.close(WebSocketStatus.policyViolation);
        return;
      }
      Map<String, dynamic> command;
      try {
        final decoded = jsonDecode(data);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        command = decoded;
      } catch (_) {
        await socket.close(WebSocketStatus.invalidFramePayloadData);
        return;
      }
      if (command['v'] != remoteProtocolVersion) {
        _send(socket, {'type': 'error', 'message': 'Versão de protocolo incompatível'});
        await socket.close();
        return;
      }
      final type = command['type'];
      if (!authorized) {
        if (type != 'pair' || _controller != null ||
            _invalidAttempts >= 15 || command['pin'] != _pin) {
          _invalidAttempts++;
          _send(socket, {'type': 'pair_denied', 'message': 'Pareamento recusado'});
          await socket.close(WebSocketStatus.policyViolation);
          return;
        }
        authorized = true;
        _controller = socket;
        _send(socket, {'type': 'paired'});
        sendState();
        onConnection?.call(true);
        return;
      }
      if (type is! String || !const {
        'play', 'pause', 'reset', 'seek', 'set_speed', 'set_font_size',
        'set_mirror', 'record_start', 'record_stop',
      }.contains(type)) {
        _send(socket, {'type': 'ack', 'id': command['id'], 'ok': false,
          'message': 'Comando desconhecido'});
        return;
      }
      final id = command['id'];
      if (id is! int || id <= 0 || processed.contains(id)) {
        _send(socket, {'type': 'ack', 'id': id, 'ok': false,
          'message': 'Identificador inválido ou comando duplicado'});
        return;
      }
      processed.add(id);
      if (processed.length > 2000) {
        await socket.close(WebSocketStatus.policyViolation);
        return;
      }
      // Serializa comandos para que play/pause e start/stop não se ultrapassem.
      commandQueue = commandQueue.then((_) async {
        try {
          await onCommand(type, command['value']);
          _send(socket, {'type': 'ack', 'id': id, 'ok': true});
          sendState();
        } catch (e) {
          _send(socket, {'type': 'ack', 'id': id, 'ok': false,
            'message': e.toString()});
        }
      });
    }, onDone: () {
      if (identical(_controller, socket)) {
        _controller = null;
        onConnection?.call(false);
      }
    }, onError: (_) {
      if (identical(_controller, socket)) {
        _controller = null;
        onConnection?.call(false);
      }
    }, cancelOnError: true);
  }

  void sendState() {
    final peer = _controller;
    if (peer == null) return;
    _send(peer, {'type': 'state', 'state': currentState()});
  }

  Future<void> stop() async {
    final peer = _controller;
    _controller = null;
    _pin = null;
    _localIp = null;
    onConnection?.call(false);
    if (peer != null) await peer.close();
    await _server?.close(force: true);
    _server = null;
  }
}

class RemoteClient {
  RemoteClient({required this.onState, required this.onStatus, required this.onError});
  final void Function(Map<String, dynamic>) onState;
  final void Function(String) onStatus;
  final void Function(String) onError;

  WebSocket? _socket;
  bool paired = false;
  int _nextId = 0;

  Future<void> connect(PairingInfo info) async {
    await disconnect();
    final socket = await WebSocket.connect('ws://${info.host}:${info.port}/remote')
        .timeout(const Duration(seconds: 7));
    _socket = socket;
    socket.pingInterval = const Duration(seconds: 15);
    socket.listen((data) {
      try {
        final parsed = jsonDecode(data as String);
        if (parsed is! Map<String, dynamic> || parsed['v'] != remoteProtocolVersion) {
          return;
        }
        switch (parsed['type']) {
          case 'paired':
            paired = true;
            onStatus('Conectado');
          case 'pair_denied':
            paired = false;
            onError('Pareamento recusado. Verifique o PIN e a rede.');
          case 'state':
            final state = parsed['state'];
            if (state is Map<String, dynamic>) onState(state);
          case 'ack':
            if (parsed['ok'] != true) onError('${parsed['message'] ?? 'Comando recusado'}');
        }
      } catch (_) { /* descarta mensagens inválidas */ }
    }, onDone: () {
      paired = false;
      onStatus('Desconectado');
    }, onError: (_) {
      paired = false;
      onError('A conexão Wi-Fi foi interrompida.');
    }, cancelOnError: true);
    socket.add(jsonEncode({'v': remoteProtocolVersion, 'type': 'pair', 'pin': info.pin}));
    onStatus('Aguardando confirmação do pareamento...');
  }

  void command(String type, [dynamic value]) {
    if (!paired || _socket == null) {
      onError('Conecte primeiro ao teleprompter.');
      return;
    }
    _socket!.add(jsonEncode({
      'v': remoteProtocolVersion,
      'id': ++_nextId,
      'type': type,
      if (value != null) 'value': value,
    }));
  }

  Future<void> disconnect() async {
    paired = false;
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close();
  }
}
