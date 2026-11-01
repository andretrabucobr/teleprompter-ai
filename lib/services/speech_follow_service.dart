import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Prova de conceito com ASR nativo. O plugin não garante ditado contínuo:
/// cada sessão é curta, e a tentativa de reinício pode ter pequenos intervalos.
class SpeechFollowService {
  SpeechFollowService({
    required this.onTranscript,
    required this.onStatus,
    required this.onError,
  });

  final void Function(String transcript, bool isFinal) onTranscript;
  final void Function(String status) onStatus;
  final void Function(String error) onError;

  final stt.SpeechToText _engine = stt.SpeechToText();
  Timer? _retry;
  bool _initialized = false;
  bool _wantsListening = false;
  bool _starting = false;
  bool _disposed = false;
  String? _localeId;

  bool get running => _wantsListening;

  Future<bool> start() async {
    if (_disposed) return false;
    _wantsListening = true;
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
          onError(error.errorMsg);
          if (error.permanent) {
            _wantsListening = false;
          } else if (_wantsListening) {
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
    await _listen();
    return _wantsListening;
  }

  Future<void> _listen() async {
    if (_disposed || !_wantsListening || _starting || _engine.isListening) return;
    _starting = true;
    try {
      await _engine.listen(
        onResult: (result) {
          if (!_disposed && _wantsListening) {
            onTranscript(result.recognizedWords, result.finalResult);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          localeId: _localeId,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!_disposed) onError('Falha ao iniciar reconhecimento: $e');
      _scheduleRestart();
    } finally {
      _starting = false;
    }
  }

  void _scheduleRestart() {
    if (_disposed || !_wantsListening) return;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 700), () {
      if (!_engine.isListening && !_starting && !_disposed) {
        _listen();
      }
    });
  }

  Future<void> stop() async {
    _wantsListening = false;
    _retry?.cancel();
    if (_initialized) await _engine.stop();
    if (!_disposed) onStatus('parado');
  }

  Future<void> dispose() async {
    await stop();
    _disposed = true;
  }
}
