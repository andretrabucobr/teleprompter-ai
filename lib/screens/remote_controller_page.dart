import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/remote_session.dart';

class RemoteControllerPage extends StatefulWidget {
  const RemoteControllerPage({super.key});

  @override
  State<RemoteControllerPage> createState() => _RemoteControllerPageState();
}

class _RemoteControllerPageState extends State<RemoteControllerPage> {
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
        const Divider(height: 30),
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
            onPressed: connected ? () => _client.command('seek', -12) : null,
            icon: const Icon(Icons.fast_rewind),
            label: const Text('Voltar'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('seek', 12) : null,
            icon: const Icon(Icons.fast_forward),
            label: const Text('Avançar'),
          ),
          OutlinedButton.icon(
            onPressed: connected ? () => _client.command('set_mirror', _state['mirror'] != true) : null,
            icon: const Icon(Icons.flip),
            label: const Text('Espelhar'),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Tamanho da fonte: ${font.round()}'),
        Row(children: [
          IconButton(onPressed: connected ? () => _client.command('set_font_size', (font - 4).clamp(20, 72)) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          const Expanded(child: Text('Fonte', textAlign: TextAlign.center)),
          IconButton(onPressed: connected ? () => _client.command('set_font_size', (font + 4).clamp(20, 72)) : null,
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
          onPressed: connected && _state['mode'] == 'camera'
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
