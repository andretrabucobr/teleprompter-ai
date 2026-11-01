import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/core/speech_alignment_tracker.dart';

void main() {
  test('não avança no silêncio nem em falas não relacionadas', () {
    final tracker = SpeechAlignmentTracker(
        ScriptMatcher('Bom dia hoje vamos apresentar a câmera profissional.'));
    expect(tracker.accept(''), isNull);
    expect(tracker.accept('sons do ambiente'), isNull);
    expect(tracker.index, -1);
  });

  test('acompanha texto e não retorna depois de uma repetição do ASR', () {
    final script = ScriptMatcher('Bom dia hoje vamos apresentar o projeto final.');
    final tracker = SpeechAlignmentTracker(script);
    expect(tracker.accept('Bom dia hoje'), 2);
    expect(tracker.accept('Bom dia hoje'), isNull); // janela duplicada
    expect(tracker.accept('hoje vamos apresentar o projeto'), 6);
    expect(tracker.accept('Bom dia hoje', isFinal: true), isNull);
    expect(tracker.index, 6);
  });

  test('aceita transcrição com uma palavra omitida no roteiro', () {
    final script = ScriptMatcher(
        'Hoje vamos apresentar nosso projeto de teleprompter inteligente.');
    final result = script.align(
      'Hoje vamos apresentar o projeto de teleprompter inteligente', -1,
      finalResult: true);
    expect(result, isNotNull);
    expect(script.words[result!.index].normalized, 'inteligente');
  });

  test('um avanço manual redefine a posição e permite reler', () {
    final script = ScriptMatcher('Bom dia hoje vamos apresentar o projeto.');
    final tracker = SpeechAlignmentTracker(script);
    expect(tracker.accept('Bom dia hoje'), 2);
    tracker.seek(0);
    expect(tracker.index, 0);
    expect(tracker.accept('dia hoje vamos'), 3);
  });

  test('texto inventado não produz correspondência', () {
    final script = ScriptMatcher('O vídeo foi gravado no estúdio da agência.');
    expect(script.align('galáxia universo tempestade arqueologia', 0), isNull);
  });
}
