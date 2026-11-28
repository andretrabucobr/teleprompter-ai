import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'wav_pcm_writer.dart';
import 'voice_trace.dart';
import 'asr_worker.dart';
import '../core/asr_word_timing.dart';
import 'streaming_asr_worker.dart';
import 'whisper_asr_worker.dart';
import 'warm_voice_cache.dart';

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
    this.onTimedTranscript,
  });

  static const int sampleRate = 16000;
  final void Function(String transcript, bool isFinal) onTranscript;
  final void Function(String status) onStatus;
  final void Function(bool speaking)? onSpeechActivity;
  final void Function(String transcript, bool isFinal, List<AsrWordTiming> words, double audioEndMs)? onTimedTranscript;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  WavPcmWriter? _writer;
  AsrWorker? _recognizer;
  late final _warmVoice = WarmVoiceCache<StreamingAsrWorker>(_createPreparedStreaming);
  bool _preloadAllowed = true;
  Future<void>? _starting;
  Future<CapturedAudio?>? _stopping;
  bool _active = false;
  bool _transcribing = false;
  Object? _streamError;

  bool get running => _active;
  bool get voicePrepared => _warmVoice.isReady;
  bool get streamingVoice => followingVoice && _recognizer is StreamingAsrWorker;
  bool get streamingHasRecentSpeechEvidence {
    final recognizer = _recognizer;
    return followingVoice && recognizer is StreamingAsrWorker && recognizer.hasRecentSpeechEvidence;
  }
  String get activeVoiceEngine {
    if (!followingVoice) return 'Inativo';
    return _recognizer is StreamingAsrWorker ? 'Nemotron streaming' : 'Whisper offline';
  }
  String get voiceMetrics {
    final recognizer = _recognizer;
    return recognizer is StreamingAsrWorker ? recognizer.metrics : '';
  }
  bool get followingVoice => _active && _transcribing;
  int get sampleCount => _writer?.sampleCount ?? 0;
  String? get currentWavPath => _writer?.path;

  /// Foreground-only warmup, with synthetic silence inside the worker.
  /// No permission request, recorder, audio samples, or WAV are involved.
  Future<StreamingAsrWorker?> _createPreparedStreaming() async {
    if (!_preloadAllowed || !await StreamingModelFiles.isBundled()) return null;
    final worker = StreamingAsrWorker(onText: onTranscript, onStatus: onStatus,
      onSpeechActivity: onSpeechActivity, onTimedTranscript: onTimedTranscript);
    final clock = Stopwatch()..start();
    voiceTrace.add('asr_preload_start');
    try {
      await worker.start();
      worker.suspend();
      voiceTrace.add('asr_preload_ready', {'elapsed_ms': clock.elapsedMilliseconds});
      return worker;
    } catch (e) {
      await worker.stop();
      voiceTrace.add('asr_preload_error', {'message': '$e'});
      return null;
    }
  }

  Future<void> prepareVoice() async {
    _preloadAllowed = true;
    if (_active || _starting != null) return;
    try {
      final ready = await _warmVoice.prepare();
      if (ready && _preloadAllowed && !_active && _starting == null) {
        onStatus('Motor de voz pronto · microfone desligado');
      }
    } catch (e) {
      voiceTrace.add('asr_preload_error', {'message': '$e'});
    }
  }

  Future<void> releasePreparedVoice() async {
    _preloadAllowed = false;
    await _warmVoice.release();
  }

  Future<void> start({required bool followVoice, bool saveAudio = true}) async {
    // Avoid opening a second recorder while the previous one is closing.
    final stopping = _stopping;
    if (stopping != null) await stopping;
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
        voiceTrace.add('asr_following_resumed');
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
        final cached = await _warmVoice.take();
        if (cached != null) {
          try {
            cached.resume();
            _recognizer = cached;
            recognizerName = 'Streaming pt-BR';
            voiceTrace.add('asr_reused', {'metrics': cached.metrics});
          } catch (e) {
            await cached.stop();
            voiceTrace.add('asr_reuse_error', {'message': '$e'});
          }
        }
        if (_recognizer == null && await StreamingModelFiles.isBundled()) {
          final online = StreamingAsrWorker(
            onText: onTranscript,
            onStatus: onStatus,
            onSpeechActivity: onSpeechActivity,
            onTimedTranscript: onTimedTranscript,
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
        if (_recognizer == null && voiceTrace.enabled && voiceTrace.recordAudio) {
          throw StateError('Diagnóstico com áudio exige Nemotron streaming. O motor não ficou disponível; o teste foi interrompido para evitar misturar outro reconhecedor.');
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
      voiceTrace.add('mic_start_requested');
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // Solicita callbacks menores do microfone; o dispositivo pode ajustar.
        streamBufferSize: 3200,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      _streamError = null;
      _active = true;
      _transcribing = followVoice;
      voiceTrace.add('mic_ready', {'engine': recognizerName, 'sample_rate': sampleRate});
      voiceTrace.beginMicCapture(engine: recognizerName, sampleRate: sampleRate);
      _subscription = stream.listen((Uint8List chunk) {
        // A falha do ASR não deve invalidar a trilha de áudio do vídeo.
        try {
          _writer?.addPcm(chunk);
        } catch (e) {
          _streamError ??= e;
          onStatus('Falha ao salvar áudio: $e');
        }
        if (_transcribing) {
          if (voiceTrace.enabled && voiceTrace.recordAudio) voiceTrace.addPcm(chunk);
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
    voiceTrace.endMicCapture(reason: 'start_failed');
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

  void resetFollowing() {
    // Both active ASR implementations reset their epoch and PCM on resume.
    // One reset per manual seek; suspend + resume previously reset twice.
    if (_transcribing) _recognizer?.resume();
  }

  /// Suspende a leitura inteligente, mas mantém o microfone e o WAV gravando.
  void pauseFollowing() {
    if (_transcribing) {
      voiceTrace.add('asr_following_paused');
      _recognizer?.suspend();
      _transcribing = false;
    }
  }

  Future<CapturedAudio?> stop({bool keepPrepared = false}) async {
    if (_starting != null) {
      try { await _starting; } catch (_) { return null; }
    }
    if (_stopping != null) return _stopping;
    if (!_active) return null;
    final pending = _stopInternal(keepPrepared: keepPrepared);
    _stopping = pending;
    try {
      return await pending;
    } finally {
      _stopping = null;
    }
  }

  Future<CapturedAudio?> _stopInternal({required bool keepPrepared}) async {
    final writer = _writer;
    final worker = _recognizer;
    // Stop ASR callbacks immediately, while the recorder still drains WAV.
    _transcribing = false;
    if (keepPrepared && worker is StreamingAsrWorker) worker.suspend();
    try {
      await _recorder?.stop();
      await _subscription?.cancel();
      voiceTrace.endMicCapture(reason: 'capture_stopped');
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
      try {
        if (keepPrepared && _preloadAllowed && worker is StreamingAsrWorker) {
          await _warmVoice.store(worker);
          voiceTrace.add('asr_cached');
        } else {
          await worker?.stop();
        }
      } finally {
        await _recorder?.dispose();
      }
      _recorder = null;
      _subscription = null;
      _writer = null;
      _recognizer = null;
      _active = false;
      _transcribing = false;
      onStatus(keepPrepared && _preloadAllowed && worker is StreamingAsrWorker
          ? 'Motor de voz pronto · microfone desligado' : 'Microfone liberado');
    }
  }

  Future<void> discard({bool keepPrepared = false}) async {
    final path = currentWavPath;
    try { await stop(keepPrepared: keepPrepared); } finally {
      if (path != null && await File(path).exists()) {
        await File(path).delete();
      }
    }
  }
}
