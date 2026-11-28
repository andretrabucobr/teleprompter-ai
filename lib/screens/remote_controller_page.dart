import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/remote_session.dart';
import '../core/script_matcher.dart';
import '../core/reading_navigation.dart';

class RemoteControllerPage extends StatefulWidget {
  const RemoteControllerPage({super.key});

  @override
  State<RemoteControllerPage> createState() => _RemoteControllerPageState();
}

class _RemoteControllerPageState extends State<RemoteControllerPage> with WidgetsBindingObserver {
  final _address = TextEditingController();
  final _port = TextEditingController();
  final _pin = TextEditingController();
  late final RemoteClient _client = RemoteClient(
    onState: (state) {
      if (mounted) setState(() => _state = state);
    },
    onStatus: (status) {
      if (mounted) setState(() => _status = status);
    },
    onError: (message) {
      if (mounted) {
        setState(() => _status = message);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    },
  );
  Map<String, dynamic> _state = {};
  String _status = 'Não conectado';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _client.reconnect();
  }

  Future<void> _scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanPairPage()),
    );
    if (!mounted || value == null) return;
    final info = PairingInfo.parse(value);
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR Code não pertence a este aplicativo.')),
      );
      return;
    }
    _address.text = info.host;
    _port.text = '${info.port}';
    _pin.text = info.pin;
    await _connect();
  }

  Future<void> _connect() async {
    final info = PairingInfo.validate(
      _address.text,
      int.tryParse(_port.text) ?? -1,
      _pin.text,
    );
    if (info == null) {
      setState(() => _status = 'Informe IP IPv4, porta e PIN de 6 dígitos.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _client.connect(info);
    } catch (e) {
      if (mounted) setState(() => _status = 'Não foi possível conectar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client.disconnect();
    _address.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _client.paired;
    final font = (_state['fontSize'] as num?)?.toDouble() ?? 36;
    final speed = (_state['speed'] as num?)?.toDouble() ?? 40;
    final playing = _state['playing'] == true;
    final recording = _state['recording'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Controle remoto')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Conecte os dois celulares na mesma rede Wi-Fi.',
            style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Ler QR Code do teleprompter'),
        ),
        const SizedBox(height: 14),
        const Text('Ou digite os dados de conexão:'),
        const SizedBox(height: 6),
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'IP local (ex.: 192.168.1.10)'),
        ),
        Row(children: [
          Expanded(child: TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Porta'),
          )),
          const SizedBox(width: 16),
          Expanded(child: TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'PIN (6 dígitos)'),
          )),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _connect,
          icon: const Icon(Icons.wifi),
          label: const Text('Conectar'),
        ),
        const SizedBox(height: 12),
        Text(_status, style: TextStyle(color: connected ? Colors.greenAccent : Colors.amberAccent)),
        if (connected) TextButton.icon(
          onPressed: () async { await _client.disconnect(); if (mounted) setState(() { _status = 'Desconectado'; _state = {}; }); },
          icon: const Icon(Icons.link_off), label: const Text('Desconectar'),
        ),
        const Divider(height: 30),
        if (_state['script'] is String) ...[
          Text('Monitor do roteiro', style: Theme.of(context).textTheme.titleLarge),
          const Text('Toque em uma palavra ou role para reposicionar.'),
          _RemoteReader(state: _state, onSeek: connected ? (index) => _client.command('seek_word', index) : null),
          if (connected && _state['undoAvailable'] == true)
            TextButton.icon(onPressed: () => _client.command('undo_seek'), icon: const Icon(Icons.undo), label: const Text('Desfazer posição')),
        ],
        Text('Comandos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: connected ? () => _client.command(playing ? 'pause' : 'play') : null,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            label: Text(playing ? 'Pausar' : 'Iniciar'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('reset') : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reiniciar'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('seek_paragraph', -1) : null,
            icon: const Icon(Icons.fast_rewind),
            label: const Text('Voltar parágrafo'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('seek_paragraph', 1) : null,
            icon: const Icon(Icons.fast_forward),
            label: const Text('Avançar parágrafo'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('set_mirror', _state['mirror'] != true) : null,
            icon: const Icon(Icons.flip),
            label: const Text('Espelhar'),
          ),
        ]),
        const SizedBox(height: 16),
        if (connected)
          DropdownButton<String>(value: _state['scrollMode'] == 'speed' ? 'speed' : 'voice',
            items: const [DropdownMenuItem(value: 'voice', child: Text('Por voz')), DropdownMenuItem(value: 'speed', child: Text('Velocidade'))],
            onChanged: recording ? null : (value) { if (value != null) _client.command('set_scroll_mode', value); }),
        Text('Tamanho da fonte: ${font.round()}'),
        Row(children: [
          IconButton(onPressed: connected ? () => _client.command('set_font_size', (font - 4).clamp(12, 200)) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          const Expanded(child: Text('Fonte', textAlign: TextAlign.center)),
          IconButton(onPressed: connected ? () => _client.command('set_font_size', (font + 4).clamp(12, 200)) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        Text('Velocidade: ${speed.round()} px/s'),
        Row(children: [
          IconButton(onPressed: connected ? () => _client.command('set_speed', (speed - 10).clamp(10, 140)) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          const Expanded(child: Text('Velocidade', textAlign: TextAlign.center)),
          IconButton(onPressed: connected ? () => _client.command('set_speed', (speed + 10).clamp(10, 140)) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        const Divider(height: 26),
        FilledButton.icon(
          onPressed: connected && _state['mode'] == 'camera' && (recording || _state['allowRemoteRecording'] == true)
              ? () => _client.command(recording ? 'record_stop' : 'record_start')
              : null,
          icon: Icon(recording ? Icons.stop_circle : Icons.fiber_manual_record),
          label: Text(recording ? 'Encerrar gravação' : 'Iniciar gravação no aparelho principal'),
        ),
        const SizedBox(height: 10),
        const Text('A gravação remota precisa estar autorizada no celular principal. '
            'O vídeo fica armazenado naquele aparelho, e não no controle remoto.'),
      ])),
    );
  }
}

class _ScanPairPage extends StatefulWidget {
  const _ScanPairPage();
  @override
  State<_ScanPairPage> createState() => _ScanPairPageState();
}

class _ScanPairPageState extends State<_ScanPairPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Escanear conexão')),
        body: MobileScanner(
          onDetect: (capture) {
            if (_handled || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null) return;
            _handled = true;
            Navigator.pop(context, value);
          },
        ),
      );
}

/// Réplica de texto com seleção de palavra e scroll sem transmissão de vídeo.
class _RemoteReader extends StatefulWidget {
  const _RemoteReader({required this.state, required this.onSeek});
  final Map<String, dynamic> state;
  final ValueChanged<int>? onSeek;
  @override
  State<_RemoteReader> createState() => _RemoteReaderState();
}
class _RemoteReaderState extends State<_RemoteReader> {
  final _scroll = ScrollController();
  final _key = GlobalKey();
  bool _dragging = false;
  String _script = '';
  List<ScriptWord> _words = [];
  double _width = 300;
  static const _style = TextStyle(color: Colors.white, fontSize: 24, height: 1.5);
  int get _index => (widget.state['readingIndex'] as int? ?? 0).clamp(0, _words.isEmpty ? 0 : _words.length-1).toInt();
  int get _highlight => widget.state['highlightIndex'] as int? ?? -1;
  TextSpan _span() {
    var at = 0;
    final spans = <InlineSpan>[];
    for (var i=0; i<_words.length; i++) {
      final w = _words[i];
      spans.add(TextSpan(text: _script.substring(at, w.start)));
      spans.add(TextSpan(text: w.text, style: i == _highlight ? const TextStyle(backgroundColor: Colors.green, color: Colors.white) : i == _index ? const TextStyle(color: Colors.greenAccent) : null));
      at=w.end;
    }
    spans.add(TextSpan(text: _script.substring(at)));
    return TextSpan(style: _style, children: spans);
  }
  TextPainter _painter() => TextPainter(text: _span(), textDirection: TextDirection.ltr, textAlign: TextAlign.center, textScaler: MediaQuery.textScalerOf(context))..layout(maxWidth: _width);
  void _sync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _dragging || _words.isEmpty) return;
      final painter = _painter();
      try {
        final w = _words[_highlight >= 0 && _highlight < _words.length ? _highlight : _index];
        final boxes = painter.getBoxesForSelection(TextSelection(baseOffset: w.start, extentOffset: w.end));
        if (boxes.isNotEmpty) _scroll.jumpTo(boxes.first.top.clamp(0.0, _scroll.position.maxScrollExtent).toDouble());
      } finally { painter.dispose(); }
    });
  }
  @override
  void initState() { super.initState(); _readScript(); _sync(); }
  void _readScript() { _script = widget.state['script'] as String? ?? ''; _words = ScriptMatcher.tokenize(_script); }
  @override
  void didUpdateWidget(covariant _RemoteReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.state['script'] != widget.state['script'];
    if (changed) _readScript();
    if (changed || oldWidget.state['readingIndex'] != widget.state['readingIndex'] || oldWidget.state['highlightIndex'] != widget.state['highlightIndex']) _sync();
  }
  void _select(Offset position) {
    if (_words.isEmpty || widget.onSeek == null) return;
    final painter = _painter();
    try { widget.onSeek!(ReadingNavigation(_script, _words).atOffset(painter.getPositionForOffset(position).offset)); }
    finally { painter.dispose(); }
  }
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Container(
    height: 300, color: Colors.black,
    child: LayoutBuilder(builder: (context, constraints) {
      _width = (constraints.maxWidth - 24).clamp(1.0, 10000.0).toDouble();
      return NotificationListener<ScrollNotification>(onNotification: (n) {
        if (n.depth != 0) return false;
        if ((n is ScrollStartNotification && n.dragDetails != null) || (n is ScrollUpdateNotification && n.dragDetails != null)) _dragging = true;
        if (n is ScrollEndNotification && _dragging) {
          _dragging = false;
          _select(Offset(1, _scroll.offset));
        }
        return false;
      }, child: SingleChildScrollView(controller: _scroll, physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 100, 12, 220),
        child: GestureDetector(onTapUp: (d) => _select(d.localPosition), child: Text.rich(_span(), key: _key, textAlign: TextAlign.center)),
      ));
    }),
  );
}
