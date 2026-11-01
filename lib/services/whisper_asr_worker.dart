import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../core/speech_activity_gate.dart';

/// Arquivos Whisper multilíngues INT8 instalados com scripts/instalar_modelo.py.
/// O tamanho dos arquivos impede incluí-los diretamente neste repositório.
class WhisperModelFiles {
  const WhisperModelFiles(this.encoder, this.decoder, this.tokens);

  final String encoder;
  final String decoder;
  final String tokens;

  static Future<WhisperModelFiles> prepare() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/whisper_multilingual_int8_v2');
    await dir.create(recursive: true);
    String chosenModel;
    try {
      chosenModel = (await rootBundle.loadString(
          'assets/models/whisper/installed-model.txt')).trim();
      if (chosenModel != 'base' && chosenModel != 'tiny') {
        throw StateError('Modelo desconhecido: $chosenModel');
      }
    } catch (error) {
      throw StateError('Modelo Whisper não incluído no build. '
          'Use scripts/instalar_modelo.py antes de compilar: $error');
    }
    final cacheMarker = File('${dir.path}/installed-model.txt');
    final cachedModel = await cacheMarker.exists()
        ? (await cacheMarker.readAsString()).trim() : '';

    Future<String> assetToFile(String name) async {
      final dst = File('${dir.path}/$name');
      if (cachedModel == chosenModel && await dst.exists() &&
          await dst.length() > 1024) return dst.path;
      final data = await rootBundle.load('assets/models/whisper/$name');
      if (data.lengthInBytes <= 1024) {
        throw StateError('Arquivo do modelo incompleto: $name');
      }
      // Arquivo temporário evita reaproveitar um modelo parcialmente copiado.
      final temporary = File('${dst.path}.part');
      await temporary.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
      if (await dst.exists()) await dst.delete();
      await temporary.rename(dst.path);
      return dst.path;
    }

    try {
      final files = WhisperModelFiles(
        await assetToFile('encoder.int8.onnx'),
        await assetToFile('decoder.int8.onnx'),
        await assetToFile('tokens.txt'),
      );
      await cacheMarker.writeAsString(chosenModel, flush: true);
      return files;
    } catch (error) {
      throw StateError('Modelo de português offline não encontrado. '
          'Execute python3 scripts/instalar_modelo.py antes de compilar. '
          'Detalhes: $error');
    }
  }
}

/// Whisper é OFFLINE, em janelas sobrepostas, e NÃO streaming nativo.
/// Fluxo PCM de gravação continua independente da inferência.
class WhisperAsrWorker {
  WhisperAsrWorker({required this.onText, required this.onStatus});

  final void Function(String text) onText;
  final void Function(String message) onStatus;

  static const int sampleRate = 16000;
  static const int _windowSamples = sampleRate * 5;
  static const int _hopSamples = sampleRate * 9 ~/ 10; // 0,9 s

  final Float32List _ring = Float32List(_windowSamples);
  final SpeechActivityGate _gate = SpeechActivityGate();
  int _total = 0;
  int _filled = 0;
  int _sinceRequest = 0;
  int _epoch = 0;
  bool _busy = false;
  bool _running = false;
  bool _following = false;
  bool _speechDetected = false;
  Isolate? _isolate;
  ReceivePort? _events;
  StreamSubscription<dynamic>? _eventSub;
  SendPort? _commands;
  Completer<void>? _stopped;

  bool get following => _running && _following;

  Future<void> start() async {
    if (_running) return;
    final files = await WhisperModelFiles.prepare();
    final ready = Completer<void>();
    final events = ReceivePort();
    _events = events;
    _eventSub = events.listen((dynamic message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'ready':
          _commands = message['port'] as SendPort;
          _running = true;
          _following = true;
          if (!ready.isCompleted) ready.complete();
          onStatus('Modelo pronto. Pode começar a falar.');
        case 'result':
          _busy = false;
          final value = message['text'];
          if (_running && _following && message['epoch'] == _epoch &&
              value is String) {
            if (value.trim().isNotEmpty) {
              onText(value);
              onStatus('Reconhecimento ativo');
            } else if (_speechDetected) {
              onStatus('Microfone captou fala, mas ainda não identificou palavras.');
            }
          }
          _requestDecode();
        case 'error':
          _busy = false;
          final description = '${message['message']}';
          onStatus('Falha no reconhecimento: $description');
          if (!ready.isCompleted) ready.completeError(StateError(description));
        case 'stopped':
          if (_stopped != null && !_stopped!.isCompleted) _stopped!.complete();
      }
    });
    try {
      _isolate = await Isolate.spawn<Map<String, Object>>(
        _whisperIsolateMain,
        <String, Object>{
          'events': events.sendPort,
          'encoder': files.encoder,
          'decoder': files.decoder,
          'tokens': files.tokens,
        },
        debugName: 'teleprompter_whisper_asr',
      );
      await ready.future.timeout(const Duration(seconds: 90));
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  /// Suspende apenas o reconhecimento; o gravador WAV não para.
  void suspend() {
    _following = false;
    _epoch++;
    _resetRecentAudio();
  }

  void resume() {
    if (!_running) throw StateError('Modelo offline não inicializado.');
    _epoch++;
    _resetRecentAudio();
    _following = true;
  }

  void _resetRecentAudio() {
    _total = 0;
    _filled = 0;
    _sinceRequest = 0;
    _gate.reset();
    _speechDetected = false;
  }

  void addPcm(Uint8List pcm) {
    if (!_running || !_following || pcm.isEmpty) return;
    _gate.addPcm(pcm);
    if (!_speechDetected && _gate.hasNewSpeech) {
      _speechDetected = true;
      onStatus('Fala detectada. Analisando em português...');
    }
    final view = ByteData.sublistView(pcm);
    for (var i = 0; i + 1 < view.lengthInBytes; i += 2) {
      _ring[_total % _windowSamples] = view.getInt16(i, Endian.little) / 32768.0;
      _total++;
      if (_filled < _windowSamples) _filled++;
      _sinceRequest++;
    }
    _requestDecode();
  }

  void _requestDecode() {
    if (_busy || !_running || !_following || _commands == null ||
        _filled < sampleRate || !_gate.recentSpeech || !_gate.hasNewSpeech) {
      return;
    }
    final atPause = _gate.justPaused && _sinceRequest > sampleRate ~/ 3;
    if (_sinceRequest < _hopSamples && !atPause) return;

    final recent = Float32List(_filled);
    final start = _total - _filled;
    for (var i = 0; i < _filled; i++) {
      recent[i] = _ring[(start + i) % _windowSamples];
    }
    _sinceRequest = 0;
    _gate.markDecoded();
    _busy = true;
    _commands!.send(<String, Object>{
      'type': 'decode',
      'epoch': _epoch,
      'samples': TransferableTypedData.fromList([recent.buffer.asUint8List()]),
    });
  }

  Future<void> stop() async {
    _following = false;
    _running = false;
    if (_commands != null) {
      _stopped = Completer<void>();
      _commands!.send({'type': 'stop'});
      try {
        await _stopped!.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        // Libera o isolate se o reconhecimento ficar bloqueado.
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    await _eventSub?.cancel();
    _eventSub = null;
    _events?.close();
    _events = null;
    _stopped = null;
    _busy = false;
    _resetRecentAudio();
  }
}

/// Decodificador isolado; a UI nunca chama recognizer.decode diretamente.
Future<void> _whisperIsolateMain(Map<String, Object> params) async {
  final out = params['events']! as SendPort;
  final commands = ReceivePort();
  sherpa.OfflineRecognizer? recognizer;
  try {
    await sherpa.initBindingsAsync();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: params['encoder']! as String,
            decoder: params['decoder']! as String,
            language: 'pt',
            task: 'transcribe',
          ),
          tokens: params['tokens']! as String,
          numThreads: 2,
          debug: false,
          modelType: 'whisper',
        ),
      ),
    );
    out.send({'type': 'ready', 'port': commands.sendPort});
    await for (final dynamic event in commands) {
      if (event is! Map) continue;
      if (event['type'] == 'stop') {
        out.send({'type': 'stopped'});
        break;
      }
      if (event['type'] != 'decode') continue;
      try {
        final bytes = (event['samples'] as TransferableTypedData).materialize();
        final samples = bytes.asFloat32List();
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(
            samples: samples, sampleRate: WhisperAsrWorker.sampleRate);
          recognizer.decode(stream);
          out.send({
            'type': 'result',
            'text': recognizer.getResult(stream).text,
            'epoch': event['epoch'],
          });
        } finally {
          stream.free();
        }
      } catch (e) {
        out.send({'type': 'error', 'message': '$e'});
      }
    }
  } catch (e) {
    out.send({'type': 'error', 'message': '$e'});
  } finally {
    recognizer?.free();
    commands.close();
  }
}
