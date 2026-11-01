import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'wav_pcm_writer.dart';
import 'asr_worker.dart';
import 'streaming_asr_worker.dart';
import 'whisper_asr_worker.dart';

class CapturedAudio {
  const CapturedAudio({
    required this.wavPath,
    required this.sampleCount,
    required this.sampleRate,
  });

  final String wavPath;
  final int sampleCount;
  final int sampleRate;
}

/// A única entrada de microfone do modo Câmera.
/// Um único stream PCM vai para WAV e (se solicitado) ASR em outro isolate.
/// A câmera deve ser criada com enableAudio:false.
class SharedAudioCapture {
  SharedAudioCapture({
    required this.onTranscript,
    required this.onStatus,
    this.onSpeechActivity,
  });

  static const int sampleRate = 16000;
  final void Function(String transcript, bool isFinal) onTranscript;
  final void Function(String status) onStatus;
  final void Function(bool speaking)? onSpeechActivity;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  WavPcmWriter? _writer;
  AsrWorker? _recognizer;
  Future<void>? _starting;
  Future<CapturedAudio?>? _stopping;
  bool _active = false;
  bool _transcribing = false;
  Object? _streamError;

  bool get running => _active;
  bool get followingVoice => _active && _transcribing;
  int get sampleCount => _writer?.sampleCount ?? 0;
  String? get currentWavPath => _writer?.path;

  Future<void> start({required bool followVoice, bool saveAudio = true}) async {
    if (_active) {
      if (saveAudio && _writer == null) {
        throw StateError('A captura atual não grava arquivo. Reinicie a sessão.');
      }
      if (followVoice && !_transcribing) {
        if (_recognizer == null) {
          throw StateError('A gravação começou sem motor de voz. '
              'Finalize antes de ativar reconhecimento.');
        }
        _recognizer!.resume();
        _transcribing = true;
      }
      return;
    }
    if (_starting != null) return _starting;
    _starting = _startInternal(followVoice, saveAudio);
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  Future<void> _startInternal(bool followVoice, bool saveAudio) async {
    try {
      final recorder = AudioRecorder();
      _recorder = recorder;
      if (!await recorder.hasPermission()) {
        throw StateError('É necessária a permissão de microfone.');
      }
      var recognizerName = '';
      if (followVoice) {
        // Preferir hipóteses parciais de streaming quando presentes no build.
        // Se a inicialização não funcionar, usar Whisper sem perder a câmera.
        if (await StreamingModelFiles.isBundled()) {
          final online = StreamingAsrWorker(
            onText: onTranscript,
            onStatus: onStatus,
            onSpeechActivity: onSpeechActivity,
          );
          try {
            await online.start();
            _recognizer = online;
            recognizerName = 'Streaming pt-BR';
          } catch (error) {
            await online.stop();
            onStatus('Streaming indisponível ($error). Tentando Whisper offline...');
          }
        }
        if (_recognizer == null) {
          final whisper = WhisperAsrWorker(
            onText: (text) => onTranscript(text, true),
            onStatus: onStatus,
            onSpeechActivity: onSpeechActivity,
          );
          await whisper.start();
          _recognizer = whisper;
          recognizerName = 'Whisper offline';
        }
      }
      if (saveAudio) {
        final temp = await getTemporaryDirectory();
        final stamp = DateTime.now().microsecondsSinceEpoch;
        _writer = await WavPcmWriter.open(
            '${temp.path}/voz_$stamp.wav', sampleRate: sampleRate);
      }
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _streamError = null;
      _active = true;
      _transcribing = followVoice;
      _subscription = stream.listen((Uint8List chunk) {
        // A falha do ASR não deve invalidar a trilha de áudio do vídeo.
        try {
          _writer?.addPcm(chunk);
        } catch (e) {
          _streamError ??= e;
          onStatus('Falha ao salvar áudio: $e');
        }
        if (_transcribing) {
          try {
            _recognizer?.addPcm(chunk);
          } catch (e) {
            onStatus('Falha na transcrição; vídeo continua gravando: $e');
            pauseFollowing();
          }
        }
      }, onError: (Object error) {
        _streamError ??= error;
        onStatus('Falha no fluxo do microfone: $error');
      });
      onStatus(followVoice ? 'Microfone único + $recognizerName ativo' : 'Microfone único ativo');
    } catch (_) {
      await _cleanupFailedStart();
      rethrow;
    }
  }

  Future<void> _cleanupFailedStart() async {
    try { await _recorder?.stop(); } catch (_) { /* ainda não iniciado */ }
    try { await _subscription?.cancel(); } catch (_) { /* já encerrado */ }
    try { await _writer?.close(); } catch (_) { /* WAV incompleto */ }
    try { await _recognizer?.stop(); } catch (_) { /* isolate indisponível */ }
    await _recorder?.dispose();
    _recorder = null;
    _writer = null;
    _subscription = null;
    _recognizer = null;
    _active = false;
    _transcribing = false;
  }

  /// Suspende a leitura inteligente, mas mantém o microfone e o WAV gravando.
  void pauseFollowing() {
    if (_transcribing) {
      _recognizer?.suspend();
      _transcribing = false;
    }
  }

  Future<CapturedAudio?> stop() async {
    if (_starting != null) {
      try { await _starting; } catch (_) { return null; }
    }
    if (_stopping != null) return _stopping;
    if (!_active) return null;
    final pending = _stopInternal();
    _stopping = pending;
    try {
      return await pending;
    } finally {
      _stopping = null;
    }
  }

  Future<CapturedAudio?> _stopInternal() async {
    final writer = _writer;
    try {
      await _recorder?.stop();
      await _subscription?.cancel();
      final path = await writer?.close();
      if (_streamError != null) {
        throw StateError('Falha no PCM durante gravação: $_streamError');
      }
      if (writer == null || path == null) return null;
      return CapturedAudio(
        wavPath: path,
        sampleCount: writer.sampleCount,
        sampleRate: sampleRate,
      );
    } finally {
      await _recognizer?.stop();
      await _recorder?.dispose();
      _recorder = null;
      _subscription = null;
      _writer = null;
      _recognizer = null;
      _active = false;
      _transcribing = false;
      onStatus('Microfone liberado');
    }
  }

  Future<void> discard() async {
    final path = currentWavPath;
    try { await stop(); } finally {
      if (path != null && await File(path).exists()) {
        await File(path).delete();
      }
    }
  }
}
