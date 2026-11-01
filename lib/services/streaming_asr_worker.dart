import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/pcm_frame_accumulator.dart';
import '../core/speech_activity_gate.dart';
import 'asr_worker.dart';

/// Nemotron 3.5 Streaming INT8. O encoder de ~627 MB é dividido em partes
/// de 8 MiB durante o build para não carregar tudo em RAM no primeiro uso.
/// Modelo de teste: pode exigir muito processamento em aparelhos antigos.
class StreamingModelFiles {
  const StreamingModelFiles(this.encoder, this.decoder, this.joiner, this.tokens);

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  static const _assets = 'assets/models/streaming';
  static const _modelId =
      'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11';

  static Future<Map<String, dynamic>> _manifest() async {
    final json = await rootBundle.loadString('$_assets/manifest.json');
    final config = jsonDecode(json) as Map<String, dynamic>;
    if (config['model'] != _modelId || config['locale'] != 'pt-BR') {
      throw StateError('Manifesto Nemotron incorreto ou modelo diferente.');
    }
    return config;
  }

  static Future<bool> isBundled() async {
    try {
      await _manifest();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<StreamingModelFiles> prepare() async {
    final config = await _manifest();
    final parts = (config['encoderParts'] as List<dynamic>).cast<String>();
    final total = config['encoderBytes'] as int;
    if (parts.isEmpty || total < 400000000 ||
        parts.any((p) => !RegExp(r'^encoder\.part\d{3}$').hasMatch(p))) {
      throw StateError('Manifesto Nemotron inválido: partes do encoder.');
    }
    final files = (config['files'] as Map<String, dynamic>);
    const names = ['decoder.int8.onnx', 'joiner.int8.onnx', 'tokens.txt'];
    for (final name in names) {
      if (files[name] is! int || (files[name] as int) < 1024) {
        throw StateError('Arquivo inválido no manifesto: $name');
      }
    }

    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/nemotron_ptbr_streaming_v1');
    await dir.create(recursive: true);
    final encoderFile = File('${dir.path}/encoder.int8.onnx');
    final marker = File('${dir.path}/installed-model.txt');
    bool cached = false;
    if (await marker.exists()) {
      cached = (await marker.readAsString()).trim() == _modelId &&
          await encoderFile.exists() && await encoderFile.length() == total;
      for (final name in names) {
        final file = File('${dir.path}/$name');
        cached = cached && await file.exists() &&
            await file.length() == (files[name] as int);
      }
    }
    if (!cached) {
      // Não reutiliza marcador de uma instalação incompleta.
      if (await marker.exists()) await marker.delete();
      final tmp = File('${encoderFile.path}.partial');
      final handle = await tmp.open(mode: FileMode.write);
      try {
        for (final part in parts) {
          final blob = await rootBundle.load('$_assets/$part');
          if (blob.lengthInBytes < 1024 || blob.lengthInBytes > 8 * 1024 * 1024) {
            throw StateError('Parte Nemotron incompleta ou grande: $part');
          }
          await handle.writeFrom(blob.buffer.asUint8List(
            blob.offsetInBytes, blob.lengthInBytes));
        }
      } finally {
        await handle.close();
      }
      if (await tmp.length() != total) {
        await tmp.delete();
        throw StateError('Encoder Nemotron incompleto no dispositivo.');
      }
      if (await encoderFile.exists()) await encoderFile.delete();
      await tmp.rename(encoderFile.path);
      for (final name in names) {
        final data = await rootBundle.load('$_assets/$name');
        if (data.lengthInBytes != (files[name] as int)) {
          throw StateError('Arquivo Nemotron incompleto: $name');
        }
        final target = File('${dir.path}/$name');
        final partial = File('${target.path}.partial');
        await partial.writeAsBytes(data.buffer.asUint8List(
          data.offsetInBytes, data.lengthInBytes), flush: true);
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
      }
      await marker.writeAsString(_modelId, flush: true);
    }
    return StreamingModelFiles(
      encoderFile.path,
      '${dir.path}/decoder.int8.onnx',
      '${dir.path}/joiner.int8.onnx',
      '${dir.path}/tokens.txt',
    );
  }
}

/// Streaming neural verdadeiro: PCM a cada 100 ms -> OnlineRecognizer.
/// A inferência ocorre em isolate próprio; a gravação não espera o decoder.
class StreamingAsrWorker implements AsrWorker {
  StreamingAsrWorker({
    required this.onText,
    required this.onStatus,
    this.onSpeechActivity,
  });

  final void Function(String text, bool isFinal) onText;
  final void Function(String status) onStatus;
  final void Function(bool speaking)? onSpeechActivity;

  final PcmFrameAccumulator _frames = PcmFrameAccumulator();
  final SpeechActivityGate _gate = SpeechActivityGate();
  ReceivePort? _events;
  StreamSubscription<dynamic>? _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  Completer<void>? _stopCompleted;
  bool _running = false;
  bool _following = false;
  bool _speaking = false;
  int _epoch = 0;
  int _queuedBytes = 0;
  int _droppedFrames = 0;
  static const int _maxPendingBytes = 3 * 16000 * 2; // backlog máx. 3 s.

  @override
  Future<void> start() async {
    if (_running) return;
    onStatus('Carregando reconhecimento streaming pt-BR...');
    final files = await StreamingModelFiles.prepare();
    final ready = Completer<void>();
    final events = ReceivePort();
    _events = events;
    _subscription = events.listen((dynamic event) {
      if (event is! Map) return;
      switch (event['type']) {
        case 'ready':
          _commands = event['port'] as SendPort;
          _running = true;
          _following = true;
          if (!ready.isCompleted) ready.complete();
          onStatus('Reconhecimento STREAMING pt-BR pronto.');
        case 'ack':
          if (event['epoch'] == _epoch) {
            _queuedBytes = (_queuedBytes - (event['bytes'] as int))
                .clamp(0, _maxPendingBytes).toInt();
          }
        case 'result':
          if (_running && _following && event['epoch'] == _epoch) {
            final value = event['text'];
            if (value is String && value.trim().isNotEmpty) {
              onText(value, event['final'] == true);
            }
          }
        case 'error':
          final details = '${event['message']}';
          onStatus('Erro no streaming: $details');
          if (!ready.isCompleted) ready.completeError(StateError(details));
        case 'stopped':
          if (_stopCompleted != null && !_stopCompleted!.isCompleted) {
            _stopCompleted!.complete();
          }
      }
    });
    try {
      _isolate = await Isolate.spawn<Map<String, Object>>(
        _streamingIsolateMain,
        <String, Object>{
          'events': events.sendPort,
          'encoder': files.encoder,
          'decoder': files.decoder,
          'joiner': files.joiner,
          'tokens': files.tokens,
        },
        debugName: 'teleprompter_streaming_ptbr',
      );
      await ready.future.timeout(const Duration(seconds: 90));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  @override
  void addPcm(Uint8List pcm) {
    if (!_running || !_following || pcm.isEmpty || _commands == null) return;
    _gate.addPcm(pcm);
    final speaking = _gate.currentlySpeaking;
    if (_speaking != speaking) {
      _speaking = speaking;
      onSpeechActivity?.call(speaking);
    }
    // O ASR recebe também o silêncio: necessário para detectar fim de frase.
    for (final frame in _frames.add(pcm)) {
      if (_queuedBytes + frame.lengthInBytes > _maxPendingBytes) {
        _droppedFrames++;
        if (_droppedFrames == 10) {
          onStatus('O celular está atrasando a transcrição; o WAV continua íntegro.');
        }
        continue;
      }
      _queuedBytes += frame.lengthInBytes;
      _commands!.send(<String, Object>{
        'type': 'audio',
        'epoch': _epoch,
        'bytes': frame.lengthInBytes,
        'pcm': TransferableTypedData.fromList([frame]),
      });
    }
  }

  @override
  void suspend() {
    _following = false;
    _epoch++;
    _resetPcm();
    _commands?.send(<String, Object>{'type': 'reset', 'epoch': _epoch});
  }

  @override
  void resume() {
    if (!_running) throw StateError('Streaming não inicializado.');
    _epoch++;
    _resetPcm();
    _commands?.send(<String, Object>{'type': 'reset', 'epoch': _epoch});
    _following = true;
  }

  void _resetPcm() {
    _frames.reset();
    _gate.reset();
    _queuedBytes = 0;
    _droppedFrames = 0;
    if (_speaking) {
      _speaking = false;
      onSpeechActivity?.call(false);
    }
  }

  @override
  Future<void> stop() async {
    _following = false;
    _running = false;
    if (_commands != null) {
      _stopCompleted = Completer<void>();
      _commands!.send(<String, Object>{'type': 'stop'});
      try {
        await _stopCompleted!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Liberação forçada se uma operação nativa estiver travada.
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    await _subscription?.cancel();
    _subscription = null;
    _events?.close();
    _events = null;
    _stopCompleted = null;
    _resetPcm();
  }
}

/// Isolate sequencial: nunca executa decode na thread de animação/preview.
Future<void> _streamingIsolateMain(Map<String, Object> config) async {
  final events = config['events']! as SendPort;
  final commands = ReceivePort();
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  try {
    await sherpa.initBindingsAsync();
    recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: config['encoder']! as String,
          decoder: config['decoder']! as String,
          joiner: config['joiner']! as String,
        ),
        tokens: config['tokens']! as String,
        numThreads: 2,
        provider: 'cpu',
        debug: false,
      ),
      enableEndpoint: true,
      rule2MinTrailingSilence: 0.9,
    ));
    stream = recognizer.createStream();
    stream.setOption(key: 'language', value: 'pt-BR');
    events.send(<String, Object>{'type': 'ready', 'port': commands.sendPort});
    var lastPartial = '';
    await for (final dynamic event in commands) {
      if (event is! Map) continue;
      if (event['type'] == 'stop') {
        events.send({'type': 'stopped'});
        break;
      }
      if (event['type'] == 'reset') {
        recognizer.reset(stream);
        lastPartial = '';
        continue;
      }
      if (event['type'] != 'audio') continue;
      final epoch = event['epoch'] as int;
      final count = event['bytes'] as int;
      try {
        final view = (event['pcm'] as TransferableTypedData).materialize();
        final bytes = view.asUint8List();
        final pcm = ByteData.sublistView(bytes);
        final samples = Float32List(bytes.lengthInBytes ~/ 2);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = pcm.getInt16(i * 2, Endian.little) / 32768.0;
        }
        stream.acceptWaveform(samples: samples, sampleRate: 16000);
        var decoded = false;
        var steps = 0;
        while (recognizer.isReady(stream) && steps++ < 200) {
          recognizer.decode(stream);
          decoded = true;
        }
        if (decoded) {
          final current = recognizer.getResult(stream).text.trim();
          if (current.isNotEmpty && current != lastPartial) {
            lastPartial = current;
            events.send(<String, Object>{
              'type': 'result', 'text': current,
              'epoch': epoch, 'final': false,
            });
          }
          if (recognizer.isEndpoint(stream)) {
            if (current.isNotEmpty) {
              events.send(<String, Object>{
                'type': 'result', 'text': current,
                'epoch': epoch, 'final': true,
              });
            }
            recognizer.reset(stream);
            lastPartial = '';
          }
        }
      } catch (error) {
        events.send({'type': 'error', 'message': '$error'});
      } finally {
        events.send({'type': 'ack', 'bytes': count, 'epoch': epoch});
      }
    }
  } catch (error) {
    events.send({'type': 'error', 'message': '$error'});
  } finally {
    stream?.free();
    recognizer?.free();
    commands.close();
  }
}
