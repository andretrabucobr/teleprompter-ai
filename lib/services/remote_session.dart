import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'remote_web_page.dart';

/// MVP para Wi-Fi local confiável. NÃO criptografa o tráfego WebSocket.
/// A publicação requer revisão de segurança e um canal autenticado/criptografado.
const remoteProtocolVersion = 1;
const remotePreferredPort = 8765;
const _lanNameChannel = MethodChannel('flowtext/lan_name');

typedef RemoteCommandHandler = Future<void> Function(String command, dynamic value);

class PairingInfo {
  const PairingInfo(this.host, this.port, this.pin, {this.webHost});
  final String host;
  final int port;
  final String pin;
  final String? webHost;
  String get webUrl => Uri(scheme: 'http', host: webHost ?? host, port: port, path: '/').toString();
  String get fallbackWebUrl => Uri(scheme: 'http', host: host, port: port, path: '/').toString();

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
  String? _controllerId;
  Future<void> _commandQueue = Future<void>.value();
  String? _localIp;
  String? _webHost;
  int _invalidAttempts = 0;

  bool get isRunning => _server != null;
  bool get hasController => _controller != null;
  PairingInfo? get pairing => _server == null || _pin == null || _localIp == null
      ? null
      : PairingInfo(_localIp!, _server!.port, _pin!, webHost: _webHost);

  Future<PairingInfo> start() async {
    if (pairing != null) return pairing!;
    final ip = await _findLocalIpv4();
    if (ip == null) throw StateError('Conecte o aparelho a uma rede Wi-Fi local.');
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, remotePreferredPort);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _localIp = ip;
    _pin = (100000 + Random.secure().nextInt(900000)).toString();
    _invalidAttempts = 0;
    _server!.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set('Cache-Control', 'no-store');
        request.response.headers.set('X-Content-Type-Options', 'nosniff');
        request.response.headers.set('X-Frame-Options', 'DENY');
        request.response.write(remoteWebPage);
        await request.response.close();
        return;
      }
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
    if (Platform.isAndroid) {
      try {
        final name = await _lanNameChannel.invokeMethod<String>('start',
          {'ip': ip, 'port': _server!.port}).timeout(const Duration(seconds: 8));
        if (name != null && RegExp(r'^[a-zA-Z0-9-]+\.local\.?$').hasMatch(name)) {
          _webHost = name.endsWith('.') ? name.substring(0, name.length - 1) : name;
        }
      } catch (_) {
        _webHost = null;
      }
    }
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
    var lastId = 0;
    final authTimeout = Timer(const Duration(seconds: 10), () {
      if (!authorized) socket.close(WebSocketStatus.policyViolation);
    });
    socket.pingInterval = const Duration(seconds: 10);
    socket.listen((data) async {
      if (data is! String || data.length > (authorized ? 650000 : 8192)) {
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
      if (data.length > 8192 && type != 'set_script') {
        await socket.close(WebSocketStatus.policyViolation);
        return;
      }
      if (!authorized) {
        final clientId = command['clientId'];
        if (type != 'pair' || _invalidAttempts >= 15 || command['pin'] != _pin || _pin == null) {
          _invalidAttempts++;
          _send(socket, {'type': 'pair_denied', 'message': 'PIN inválido ou sessão encerrada'});
          await socket.close(WebSocketStatus.policyViolation);
          return;
        }
        final validId = clientId is String && RegExp(r'^[a-zA-Z0-9_-]{16,100}$').hasMatch(clientId);
        if (_controller != null && (!validId || clientId != _controllerId)) {
          _send(socket, {'type': 'busy', 'message': 'Outro controle está conectado'});
          await socket.close(WebSocketStatus.policyViolation);
          return;
        }
        final previous = _controller;
        authorized = true;
        authTimeout.cancel();
        _controller = socket;
        _controllerId = validId ? clientId as String : null;
        _invalidAttempts = 0;
        if (previous != null) unawaited(previous.close().then<void>((_) {}, onError: (Object _) {}));
        _send(socket, {'type': 'paired'});
        sendState();
        onConnection?.call(true);
        return;
      }
      if (!identical(_controller, socket)) return;
      if (type == 'ping') { _send(socket, {'type': 'pong'}); return; }
      if (type is! String || !const {
        'play', 'pause', 'reset', 'seek', 'set_speed', 'set_font_size',
        'set_mirror', 'record_start', 'record_stop', 'seek_word',
        'seek_paragraph', 'undo_seek', 'set_scroll_mode', 'set_script',
      }.contains(type)) {
        _send(socket, {'type': 'ack', 'id': command['id'], 'ok': false,
          'message': 'Comando desconhecido'});
        return;
      }
      final id = command['id'];
      if (id is! int || id <= lastId) {
        _send(socket, {'type': 'ack', 'id': id, 'ok': false,
          'message': 'Identificador inválido ou comando duplicado'});
        return;
      }
      lastId = id;
      // Serializa comandos para que play/pause e start/stop não se ultrapassem.
      _commandQueue = _commandQueue.then((_) async {
        if (!identical(_controller, socket)) return;
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
      authTimeout.cancel();
      if (identical(_controller, socket)) {
        _controller = null;
        onConnection?.call(false);
      }
    }, onError: (_) {
      authTimeout.cancel();
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
    _controllerId = null;
    _localIp = null;
    _webHost = null;
    if (Platform.isAndroid) {
      try { await _lanNameChannel.invokeMethod<void>('stop').timeout(const Duration(seconds: 3)); } catch (_) {}
    }
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
  PairingInfo? _desired;
  Timer? _retry;
  Timer? _pairTimeout;
  bool paired = false;
  bool _connecting = false;
  int _generation = 0;
  int _attempt = 0;
  int _nextId = 0;
  final String _clientId = List.generate(24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();

  Future<void> connect(PairingInfo info) async {
    await disconnect();
    _desired = info;
    await _open();
  }

  Future<void> _open() async {
    final info = _desired;
    if (info == null || _connecting || _socket != null) return;
    final generation = ++_generation;
    _connecting = true;
    onStatus('Conectando...');
    try {
      final socket = await WebSocket.connect('ws://${info.host}:${info.port}/remote')
          .timeout(const Duration(seconds: 7));
      if (generation != _generation || _desired == null) { await socket.close(); return; }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 10);
      _pairTimeout = Timer(const Duration(seconds: 8), () => _lost(socket));
      socket.listen((data) {
        if (!identical(socket, _socket)) return;
        try {
          final parsed = jsonDecode(data as String);
          if (parsed is! Map<String, dynamic> || parsed['v'] != remoteProtocolVersion) return;
          switch (parsed['type']) {
            case 'paired':
              _pairTimeout?.cancel();
              paired = true;
              _attempt = 0;
              onStatus('Conectado');
            case 'pair_denied':
              _desired = null;
              _lost(socket);
              onError('Pareamento recusado. Verifique o PIN.');
            case 'busy':
              onStatus('Outro controle conectado. Tentando novamente...');
              _lost(socket);
            case 'state':
              final state = parsed['state'];
              if (paired && state is Map<String, dynamic>) onState(state);
            case 'ack':
              if (parsed['ok'] != true) onError('${parsed['message'] ?? 'Comando recusado'}');
          }
        } catch (_) { /* mensagem inválida */ }
      }, onDone: () => _lost(socket), onError: (_) => _lost(socket), cancelOnError: true);
      socket.add(jsonEncode({'v': remoteProtocolVersion, 'type': 'pair', 'pin': info.pin, 'clientId': _clientId}));
    } catch (_) {
      if (generation == _generation) _scheduleRetry();
    } finally {
      if (generation == _generation) _connecting = false;
    }
  }

  void _lost(WebSocket socket) {
    if (!identical(_socket, socket)) return;
    _pairTimeout?.cancel();
    _socket = null;
    paired = false;
    unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (_desired == null) { onStatus('Desconectado'); return; }
    onStatus('Reconectando...');
    final delay = min(8, 1 << min(_attempt++, 3));
    _retry = Timer(Duration(seconds: delay), () => _open());
  }

  // Ao desbloquear, substitui a conexão possivelmente suspensa sem repetir comandos.
  Future<void> reconnect() async {
    if (_desired == null) return;
    _retry?.cancel();
    _pairTimeout?.cancel();
    ++_generation;
    _connecting = false;
    final old = _socket;
    _socket = null;
    paired = false;
    if (old != null) unawaited(old.close().then<void>((_) {}, onError: (Object _) {}));
    await _open();
  }

  void command(String type, [dynamic value]) {
    final socket = _socket;
    if (!paired || socket == null) return;
    try {
      socket.add(jsonEncode({'v': remoteProtocolVersion, 'id': ++_nextId,
        'type': type, if (value != null) 'value': value}));
    } catch (_) { _lost(socket); }
  }

  Future<void> disconnect() async {
    _desired = null;
    ++_generation;
    _connecting = false;
    _retry?.cancel();
    _pairTimeout?.cancel();
    paired = false;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
  }
}
