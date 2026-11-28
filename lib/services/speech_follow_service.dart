import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Prova de conceito com ASR nativo. O plugin não garante ditado contínuo:
/// cada sessão é curta, e a tentativa de reinício pode ter pequenos intervalos.
class SpeechFollowService {
  SpeechFollowService({
    required this.onTranscript,
    required this.onStatus,
    required this.onError,
    this.onUnavailable,
  });

  final void Function(String transcript, bool isFinal) onTranscript;
  final void Function(String status) onStatus;
  final void Function(String error) onError;
  final void Function()? onUnavailable;
  int _consecutiveFailures = 0;
  bool _startingSession = false;

  final stt.SpeechToText _engine = stt.SpeechToText();
  Timer? _retry;
  bool _initialized = false;
  bool _onDevice = false;
  bool _wantsListening = false;
  bool _starting = false;
  bool _disposed = false;
  String? _localeId;
  int _generation = 0;
  Future<void> _resetQueue = Future<void>.value();

  bool get running => _wantsListening;

  Future<bool> start({bool onDevice = false}) async {
    if (_disposed) return false;
    _onDevice = onDevice;
    _consecutiveFailures = 0;
    _wantsListening = true;
    _startingSession = true;
    try {
    if (!_initialized) {
      final ready = await _engine.initialize(
        options: [stt.SpeechToText.androidNoBluetooth],
        onStatus: (status) {
          if (!_disposed) onStatus(status);
          if (_wantsListening &&
              (status == stt.SpeechToText.doneStatus ||
                  status == stt.SpeechToText.notListeningStatus)) {
            _scheduleRestart();
          }
        },
        onError: (error) {
          if (_disposed) return;
          if (!_wantsListening) return;
          final message = error.errorMsg;
          // Silêncio normal: o serviço pode encerrar a sessão sem resultado.
          final normalEnd = message == 'error_no_match' ||
              message == 'error_speech_timeout';
          if (normalEnd) {
            _consecutiveFailures = 0;
            _scheduleRestart();
            return;
          }
          onError(message);
          final unavailable = error.permanent || message.contains('language') ||
              message.contains('network') || message.contains('permission');
          if (unavailable || ++_consecutiveFailures >= 3) {
            _failUnavailable();
          } else {
            _scheduleRestart();
          }
        },
      );
      if (!ready) {
        _wantsListening = false;
        onError('Microfone/reconhecimento de voz indisponível ou sem permissão.');
        return false;
      }
      _initialized = true;
      final locales = await _engine.locales();
      final portuguese = locales.where((l) => l.localeId.toLowerCase().startsWith('pt'));
      if (portuguese.isNotEmpty) {
        final brazil = portuguese.where((l) => l.localeId.toLowerCase().contains('br'));
        _localeId = brazil.isNotEmpty ? brazil.first.localeId : portuguese.first.localeId;
      }
    }
    if (_onDevice && _localeId == null) return false;
    await _listen();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (_wantsListening && !_engine.isListening && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return _wantsListening && _engine.isListening;
    } finally {
      _startingSession = false;
    }
  }

  void _failUnavailable() {
    _wantsListening = false;
    _retry?.cancel();
    if (!_startingSession) onUnavailable?.call();
  }

  Future<void> _listen() async {
    if (_disposed || !_wantsListening || _starting || _engine.isListening) return;
    _starting = true;
    final generation = ++_generation;
    try {
      await _engine.listen(
        onResult: (result) {
          if (!_disposed && _wantsListening && generation == _generation) {
            _consecutiveFailures = 0;
            onTranscript(result.recognizedWords, result.finalResult);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          onDevice: _onDevice,
          listenMode: stt.ListenMode.dictation,
          localeId: _localeId,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!_disposed) onError('Falha ao iniciar reconhecimento: $e');
      if (++_consecutiveFailures >= 3) {
        _failUnavailable();
      } else {
        _scheduleRestart();
      }
    } finally {
      _starting = false;
    }
  }

  void _scheduleRestart() {
    if (_disposed || !_wantsListening) return;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: _onDevice ? 250 : 700), () {
      if (!_engine.isListening && !_starting && !_disposed) {
        _listen();
      }
    });
  }

  Future<void> reset() {
    ++_generation;
    _retry?.cancel();
    _resetQueue = _resetQueue.catchError((Object _) {}).then((_) async {
      if (!_wantsListening || _disposed) return;
      await _engine.cancel();
      _retry?.cancel();
      if (_wantsListening && !_disposed) {
        await _listen();
        if (!_engine.isListening) _scheduleRestart();
      }
    });
    return _resetQueue;
  }

  Future<void> stop() async {
    ++_generation;
    _wantsListening = false;
    _retry?.cancel();
    if (_initialized) await _engine.cancel();
    if (!_disposed) onStatus('parado');
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
  }
}
