import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/voice_scroll_gate.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 12);

  test('nenhum resultado move o texto antes de a voz começar', () {
    final gate = VoiceScrollGate();
    expect(gate.decide(hasActivityDetector: true, at: t0),
        VoiceScrollDecision.ignore);
    gate.onSpeechActivity(false, at: t0);
    expect(gate.decide(hasActivityDetector: true, at: t0),
        VoiceScrollDecision.ignore);
  });

  test('ao falar o reconhecimento pode avançar; silêncio congela a tela', () {
    final gate = VoiceScrollGate();
    gate.onSpeechActivity(true, at: t0);
    expect(gate.decide(hasActivityDetector: true, at: t0),
        VoiceScrollDecision.advance);
    gate.onSpeechActivity(false, at: t0.add(const Duration(seconds: 1)));
    expect(gate.isSpeaking, isFalse);
    final correction = gate.decide(hasActivityDetector: true,
        at: t0.add(const Duration(milliseconds: 1400)));
    expect(correction, VoiceScrollDecision.highlightOnly);
    gate.onConfirmed(correction);
    // Replicações do ASR (inclusive finais) não disparam novas rolagens.
    expect(gate.decide(hasActivityDetector: true,
        at: t0.add(const Duration(milliseconds: 1450))),
        VoiceScrollDecision.ignore);
  });

  test('não aceita resultados muito atrasados ou após nova pausa', () {
    final gate = VoiceScrollGate();
    gate.onSpeechActivity(true, at: t0);
    gate.onSpeechActivity(false, at: t0.add(const Duration(seconds: 1)));
    expect(gate.decide(hasActivityDetector: true,
        at: t0.add(const Duration(milliseconds: 2000))),
        VoiceScrollDecision.ignore);
    gate.onSpeechActivity(true, at: t0.add(const Duration(seconds: 3)));
    expect(gate.decide(hasActivityDetector: true,
        at: t0.add(const Duration(seconds: 3))),
        VoiceScrollDecision.advance);
  });

  test('recomeço limpa a autorização de resultados antigos', () {
    final gate = VoiceScrollGate();
    gate.onSpeechActivity(true, at: t0);
    gate.reset();
    expect(gate.decide(hasActivityDetector: true, at: t0),
        VoiceScrollDecision.ignore);
  });

  test('ASR nativo continua possível como fallback sem VAD PCM', () {
    final gate = VoiceScrollGate();
    expect(gate.decide(hasActivityDetector: false, at: t0),
        VoiceScrollDecision.advance);
  });
}
