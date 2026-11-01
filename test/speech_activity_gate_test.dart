import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/speech_activity_gate.dart';

Uint8List syntheticPcm(double amplitude, int frames) {
  final out = Uint8List(frames * SpeechActivityGate.samplesPerFrame * 2);
  final data = ByteData.sublistView(out);
  final value = (amplitude * 32767).toInt();
  for (var i = 0; i < frames * SpeechActivityGate.samplesPerFrame; i++) {
    // Alternar o sinal mantém RMS previsível sem precisar de áudio real.
    data.setInt16(i * 2, i.isEven ? value : -value, Endian.little);
  }
  return out;
}

void main() {
  test('silêncio não dispara reconhecimento de fala', () {
    final gate = SpeechActivityGate();
    gate.addPcm(syntheticPcm(0, 120));
    expect(gate.recentSpeech, isFalse);
    expect(gate.hasNewSpeech, isFalse);
  });

  test('fala simulada habilita decodificação e reset não mantém voz velha', () {
    final gate = SpeechActivityGate();
    gate.addPcm(syntheticPcm(.025, 30));
    expect(gate.recentSpeech, isTrue);
    expect(gate.hasNewSpeech, isTrue);
    gate.markDecoded();
    expect(gate.hasNewSpeech, isFalse);
    gate.reset();
    expect(gate.recentSpeech, isFalse);
  });

  test('fala de volume baixo é detectada sem avançar no silêncio', () {
    final gate = SpeechActivityGate();
    gate.addPcm(syntheticPcm(0, 60));
    expect(gate.recentSpeech, isFalse);
    gate.addPcm(syntheticPcm(.0042, 14));
    expect(gate.recentSpeech, isTrue);
    expect(gate.hasNewSpeech, isTrue);
  });

  test('voz antiga expira durante pausa longa', () {
    final gate = SpeechActivityGate();
    gate.addPcm(syntheticPcm(.025, 30));
    gate.addPcm(syntheticPcm(0, 140));
    expect(gate.recentSpeech, isFalse);
  });
}
