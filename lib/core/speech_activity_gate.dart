import 'dart:math' as math;
import 'dart:typed_data';

/// Filtro de energia para EVITAR decodificar silêncio. Não é um VAD neural:
/// ruído contínuo e voz muito baixa exigem testes e calibração nos aparelhos.
/// PCM16 mono, 16 kHz, janelas de 20 ms.
class SpeechActivityGate {
  static const int sampleRate = 16000;
  static const int samplesPerFrame = 320;
  static const int historyFrames = 300; // 6 s

  final List<int> _history = List<int>.filled(historyFrames, 0);
  int _historyCursor = 0;
  int _speechFrames = 0;
  int _newSpeechFrames = 0;
  int _frameCount = 0;
  int _lastSpeechFrame = -100000;
  int _frameSamples = 0;
  double _squareSum = 0;
  double _noiseFloor = .0012;

  int get newSpeechFrames => _newSpeechFrames;
  int get recentSpeechFrames => _speechFrames;
  // Menor sensibilidade mínima para vozes baixas, mas sempre relativa ao
  // ruído ambiente. Isto não substitui um VAD neural.
  bool get recentSpeech => _speechFrames >= 8 &&
      (_frameCount - _lastSpeechFrame) < 110; // até 2,2 s após a fala
  bool get justPaused => _frameCount - _lastSpeechFrame >= 23 &&
      _frameCount - _lastSpeechFrame <= 70;
  bool get hasNewSpeech => _newSpeechFrames >= 7;

  void addPcm(Uint8List bytes) {
    final pcm = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < pcm.lengthInBytes; i += 2) {
      final sample = pcm.getInt16(i, Endian.little) / 32768.0;
      _squareSum += sample * sample;
      _frameSamples++;
      if (_frameSamples == samplesPerFrame) {
        _recordFrame(math.sqrt(_squareSum / samplesPerFrame));
        _frameSamples = 0;
        _squareSum = 0;
      }
    }
  }

  void _recordFrame(double rms) {
    final threshold = math.max(.0030, _noiseFloor * 2.3);
    final spoken = rms >= threshold;
    if (!spoken) {
      _noiseFloor = (_noiseFloor * .96 + rms * .04).clamp(.0001, .04).toDouble();
    }
    _speechFrames -= _history[_historyCursor];
    final flag = spoken ? 1 : 0;
    _history[_historyCursor] = flag;
    _speechFrames += flag;
    _historyCursor = (_historyCursor + 1) % historyFrames;
    _frameCount++;
    if (spoken) {
      _lastSpeechFrame = _frameCount;
      _newSpeechFrames++;
    }
  }

  void markDecoded() => _newSpeechFrames = 0;

  void reset() {
    _history.fillRange(0, _history.length, 0);
    _historyCursor = 0;
    _speechFrames = 0;
    _newSpeechFrames = 0;
    _frameCount = 0;
    _lastSpeechFrame = -100000;
    _frameSamples = 0;
    _squareSum = 0;
    _noiseFloor = .0012;
  }
}
