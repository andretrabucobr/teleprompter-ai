import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/core/speech_alignment_tracker.dart';

void main() {
  test('hipóteses parciais devem avançar sem aguardar resultado final', () {
    final tracker = SpeechAlignmentTracker(
      ScriptMatcher('Bom dia hoje vamos apresentar o novo teleprompter.'),
    );
    expect(tracker.accept('Bom dia', isFinal: false), 1);
    expect(tracker.accept('Bom dia hoje', isFinal: false), 2);
    expect(tracker.accept('Bom dia hoje', isFinal: true), isNull);
    expect(tracker.accept('hoje vamos apresentar', isFinal: false), 4);
  });

  test('hipóteses idênticas não provocam novos saltos', () {
    final tracker = SpeechAlignmentTracker(
      ScriptMatcher('Hoje vamos gravar um vídeo com texto antecipado.'),
    );
    expect(tracker.accept('Hoje vamos gravar', isFinal: false), 2);
    expect(tracker.accept('Hoje vamos gravar', isFinal: false), isNull);
    expect(tracker.index, 2);
  });
}
