import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/asr_word_timing.dart';
import '../core/pcm_frame_accumulator.dart';
import '../core/speech_activity_gate.dart';
import 'asr_worker.dart';
import 'voice_trace.dart';

/// Nemotron 3.5 Streaming INT8. O encoder de ~627 MB é dividido em partes
/// de 8 MiB durante o build para não carregar tudo em RAM no primeiro uso.
/// Modelo de teste: pode exigir muito processamento em aparelhos antigos.
class StreamingModelFiles {
  const StreamingModelFiles(this.encoder, this.decoder, this.joiner, this.tokens, {this.modelId = 'unknown'});

  final String modelId;

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  static const _assets = 'assets/models/streaming';
  static const _modelIds = {
    'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-80ms-int8-2026-06-11',
    'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-160ms-int8-2026-06-11',
    'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-320ms-int8-2026-06-11',
    'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11',
  };

  static Future<Map<String, dynamic>> _manifest() async {
    final json = await rootBundle.loadString('$_assets/manifest.json');
    final config = jsonDecode(json) as Map<String, dynamic>;
    if (!_modelIds.contains(config['model']) || config['locale'] != 'pt-BR') {
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
    final modelId = config['model'] as String;
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
      cached = (await marker.readAsString()).trim() == modelId &&
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
      await marker.writeAsString(modelId, flush: true);
    }
    return StreamingModelFiles(
      encoderFile.path,
      '${dir.path}/decoder.int8.onnx',
      '${dir.path}/joiner.int8.onnx',
      '${dir.path}/tokens.txt',
      modelId: modelId,
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
    this.onTimedTranscript,
  });

  final void Function(String text, bool isFinal) onText;
  final void Function(String status) onStatus;
  final void Function(bool speaking)? onSpeechActivity;
  final void Function(String text, bool isFinal, List<AsrWordTiming> words, double audioEndMs)? onTimedTranscript;

  final PcmFrameAccumulator _frames = PcmFrameAccumulator(frameBytes: 1600); // 50 ms: menor overhead de mensagens
  final SpeechActivityGate _gate = SpeechActivityGate(minimumSpeechFrames: 2);
  bool get hasRecentSpeechEvidence => _running && _following && _gate.hasRecentSpeechEvidence;
  ReceivePort? _events;
  StreamSubscription<dynamic>? _subscription;
  Isolate? _isolate;
  SendPort? _commands;
  Completer<void>? _stopCompleted;
  bool _running = false;
  bool _following = false;
  bool _speaking = false;
  int _epoch = 0;
  int _frameSequence = 0;
  int _captureBytes = 0;
  int _queuedBytes = 0;
  int _droppedFrames = 0;
  static const int _maxPendingBytes = 3 * 16000 * 2; // limite de segurança, não latência alvo.
  int _lastLagWarningAt = 0;
  int _peakQueuedBytes = 0;
  int _processedBytes = 0;
  int _processingMicros = 0;
  int? _firstPartialDelay;
  int _startupMs = 0;
  int _warmupMs = 0;
  int? _firstDecodeMs;
  int _threads = 2;
  String _modelId = 'unknown';
  String get metrics {
    final rtf = _processedBytes == 0 ? 'aguardando' : (_processingMicros / (_processedBytes * 31.25)).toStringAsFixed(2);
    final first = _firstPartialDelay == null ? 'aguardando' : '$_firstPartialDelay ms';
    return 'CPU: $_threads threads · RTF: $rtf\nCarga: $_startupMs ms (aquecimento: $_warmupMs ms)\nPrimeira inferência real: ${_firstDecodeMs ?? 0} ms · 1ª hipótese após voz: $first\nFila: ${(_queuedBytes / 32).round()} ms · pico: ${(_peakQueuedBytes / 32).round()} ms · descartes: $_droppedFrames';
  }
  final Stopwatch _clock = Stopwatch();
  int? _speechOnsetMs;
  bool _firstPartialReported = false;

  @override
  Future<void> start() async {
    if (_running) return;
    onStatus('Carregando reconhecimento streaming pt-BR...');
    final startup = Stopwatch()..start();
    _threads = Platform.numberOfProcessors >= 8 ? 4 : 2;
    final files = await StreamingModelFiles.prepare();
    _modelId = files.modelId;
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
          _startupMs = startup.elapsedMilliseconds;
          _warmupMs = event['warmupMs'] as int? ?? 0;
          _clock..reset()..start();
          voiceTrace.add('asr_ready', {'startup_ms': _startupMs, 'warmup_ms': _warmupMs, 'threads': _threads, 'model': files.modelId});
          if (!ready.isCompleted) ready.complete();
          onStatus('Reconhecimento STREAMING pt-BR pronto.');
        case 'ack':
          if (event['epoch'] == _epoch) {
            _processedBytes += event['bytes'] as int;
            _processingMicros += (event['micros'] as int? ?? 0);
            if (event['decodeMs'] is int) _firstDecodeMs ??= event['decodeMs'] as int;
            _queuedBytes = (_queuedBytes - (event['bytes'] as int))
                .clamp(0, _maxPendingBytes).toInt();
            if (voiceTrace.enabled) voiceTrace.add('asr_ack', {
              'epoch': _epoch, 'frame': event['frame'], 'audio_end_ms': event['audioEndMs'],
              'queue_wait_us': event['queueWaitUs'], 'processing_us': event['micros'],
              'decode_ms': event['decodeMs'], 'decode_steps': event['decodeSteps'],
              'pending_ms': _queuedBytes / 32, 'dropped_frames': _droppedFrames,
              'rtf': _processedBytes == 0 ? null : _processingMicros / (_processedBytes * 31.25),
            });
          }
        case 'result':
          if (_running && _following && event['epoch'] == _epoch) {
            final value = event['text'];
            if (value is String && value.trim().isNotEmpty) {
              if (voiceTrace.enabled) voiceTrace.add('asr_result', {
                'epoch': _epoch, 'frame': event['frame'], 'audio_end_ms': event['audioEndMs'],
                'text': value, 'final': event['final'] == true,
                'worker_emitted_us': event['emittedUs'], 'pending_ms': _queuedBytes / 32,
              });
              final isFinal = event['final'] == true;
              final tokenValues = (event['tokens'] as List?)?.cast<String>() ?? const <String>[];
              final timeValues = (event['timestamps'] as List?)?.map((value) => (value as num).toDouble()).toList() ?? const <double>[];
              final timedWords = SentencePieceWordDecoder.decode(tokenValues, timeValues);
              if (onTimedTranscript != null && timedWords.isNotEmpty) {
                onTimedTranscript!(value, isFinal, timedWords, (event['audioEndMs'] as num?)?.toDouble() ?? 0);
              } else {
                onText(value, isFinal);
              }
              if (!_firstPartialReported && _speechOnsetMs != null) {
                _firstPartialReported = true;
                final elapsed = _clock.elapsedMilliseconds - _speechOnsetMs!;
                _firstPartialDelay = elapsed;
                onStatus('Streaming · primeira hipótese: ${elapsed} ms após início detectado');
              }
            }
          }
        case 'error':
          final details = '${event['message']}';
          voiceTrace.add('asr_error', {'message': details});
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
          'threads': _threads,
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
    _captureBytes += pcm.lengthInBytes;
    if (voiceTrace.enabled) voiceTrace.add('pcm_received', {
      'epoch': _epoch, 'bytes': pcm.lengthInBytes, 'audio_end_ms': _captureBytes / 32,
      'speech': _gate.currentlySpeaking, 'pending_ms': _queuedBytes / 32,
    });
    final speaking = _gate.currentlySpeaking;
    if (_speaking != speaking) {
      _speaking = speaking;
      if (speaking && _speechOnsetMs == null) _speechOnsetMs = _clock.elapsedMilliseconds;
      onSpeechActivity?.call(speaking);
    }
    // O ASR recebe também o silêncio: necessário para detectar fim de frase.
    for (final frame in _frames.add(pcm)) {
      if (_queuedBytes + frame.lengthInBytes > _maxPendingBytes) {
        _droppedFrames++;
        if (voiceTrace.enabled) voiceTrace.add('asr_drop', {'epoch': _epoch, 'dropped_frames': _droppedFrames, 'pending_ms': _queuedBytes / 32});
        if (_droppedFrames == 10) {
          onStatus('O celular está atrasando a transcrição; o WAV continua íntegro.');
        }
        continue;
      }
      _queuedBytes += frame.lengthInBytes;
      if (_queuedBytes > _peakQueuedBytes) _peakQueuedBytes = _queuedBytes;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_queuedBytes > 16000 * 2 && now - _lastLagWarningAt >= 5000) {
        _lastLagWarningAt = now;
        onStatus('ASR com fila de ${(_queuedBytes / 32).round()} ms de áudio.');
      }
      _commands!.send(<String, Object>{
        'type': 'audio',
        'epoch': _epoch,
        'bytes': frame.lengthInBytes,
        'frame': ++_frameSequence,
        'audioEndMs': _captureBytes / 32,
        'sentUs': Timeline.now,
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
    voiceTrace.add('asr_resume', {'model': _modelId, 'threads': _threads, 'epoch': _epoch});
  }

  void _resetPcm() {
    voiceTrace.add('asr_reset', {'epoch': _epoch, 'metrics': metrics});
    _frames.reset();
    _gate.reset();
    _captureBytes = 0;
    _queuedBytes = 0;
    _droppedFrames = 0;
    _peakQueuedBytes = 0;
    _processedBytes = 0;
    _processingMicros = 0;
    _firstPartialDelay = null;
    _firstDecodeMs = null;
    _speechOnsetMs = null;
    _firstPartialReported = false;
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
        numThreads: config['threads']! as int,
        provider: 'cpu',
        debug: false,
      ),
      enableEndpoint: true,
      rule2MinTrailingSilence: 0.9,
    ));
    // Execute a primeira inferência antes de anunciar que o microfone pode
    // ser aberto. Áudio sintético de silêncio, nunca áudio do usuário.
    final warmup = Stopwatch()..start();
    final warmStream = recognizer.createStream();
    try {
      warmStream.setOption(key: 'language', value: 'pt-BR');
      warmStream.acceptWaveform(samples: Float32List(32000), sampleRate: 16000);
      var steps = 0;
      while (recognizer.isReady(warmStream) && steps++ < 32) {
        recognizer.decode(warmStream);
      }
    } finally {
      warmStream.free();
    }
    // Uma sessão nova impede que o silêncio de aquecimento afete o cursor.
    stream = recognizer.createStream();
    stream.setOption(key: 'language', value: 'pt-BR');
    events.send(<String, Object>{'type': 'ready', 'port': commands.sendPort,
      'warmupMs': warmup.elapsedMilliseconds});
    var lastPartial = '';
    var lastTimedSignature = '';
    await for (final dynamic event in commands) {
      if (event is! Map) continue;
      if (event['type'] == 'stop') {
        events.send({'type': 'stopped'});
        break;
      }
      if (event['type'] == 'reset') {
        recognizer.reset(stream);
        lastPartial = '';
        lastTimedSignature = '';
        continue;
      }
      if (event['type'] != 'audio') continue;
      final epoch = event['epoch'] as int;
      final count = event['bytes'] as int;
      final processing = Stopwatch()..start();
      final queueWaitUs = Timeline.now - (event['sentUs'] as int);
      int? decodeMs;
      var decodeSteps = 0;
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
          final decodeClock = Stopwatch()..start();
          recognizer.decode(stream);
          decodeSteps++;
          decodeMs ??= decodeClock.elapsedMilliseconds;
          decoded = true;
          // Entregue cada hipótese alterada sem esperar drenar o áudio pronto.
          final snapshot = recognizer.getResult(stream);
          final partial = snapshot.text.trim();
          final timedSignature = '${snapshot.tokens.join('|')}@${snapshot.timestamps.join('|')}';
          if (partial.isNotEmpty && (partial != lastPartial || timedSignature != lastTimedSignature)) {
            lastPartial = partial;
            lastTimedSignature = timedSignature;
            events.send(<String, Object>{
              'type': 'result', 'text': partial,
              'tokens': snapshot.tokens, 'timestamps': snapshot.timestamps,
              'epoch': epoch, 'final': false,
              'frame': event['frame'], 'audioEndMs': event['audioEndMs'], 'emittedUs': Timeline.now,
            });
          }
        }
        if (decoded) {
          final current = lastPartial;
          if (recognizer.isEndpoint(stream)) {
            if (current.isNotEmpty) {
              events.send(<String, Object>{
                'type': 'result', 'text': current,
                'tokens': recognizer.getResult(stream).tokens,
                'timestamps': recognizer.getResult(stream).timestamps,
                'epoch': epoch, 'final': true,
                'frame': event['frame'], 'audioEndMs': event['audioEndMs'], 'emittedUs': Timeline.now,
              });
            }
            recognizer.reset(stream);
            lastPartial = '';
            lastTimedSignature = '';
          }
        }
      } catch (error) {
        events.send({'type': 'error', 'message': '$error'});
      } finally {
        events.send({'type': 'ack', 'bytes': count, 'epoch': epoch,
          'micros': processing.elapsedMicroseconds,
          'frame': event['frame'], 'audioEndMs': event['audioEndMs'],
          'queueWaitUs': queueWaitUs, 'decodeSteps': decodeSteps,
          if (decodeMs != null) 'decodeMs': decodeMs});
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
