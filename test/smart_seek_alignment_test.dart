import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/core/speech_alignment_tracker.dart';

void main() {
  test('palavra adjacente curta e parcial avança sem aguardar final', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('Bom dia hoje vamos gravar.'));
    expect(tracker.accept('Bom'), 0);
    expect(tracker.accept('Bom dia'), 1);
    expect(tracker.accept('Bom dia hoje'), 2);
    expect(tracker.accept('Bom dia hoje', isFinal: true), isNull);
  });
  test('retorno experimental somente em nova fala inequívoca', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('Céu azul ilumina montanhas distantes. Nosso projeto começa nesta manhã tranquila. Agora concluímos esta apresentação.'));
    tracker.seek(10);
    tracker.accept('Agora concluímos esta apresentação', isFinal: true, allowRewind: true);
    expect(tracker.index, 14);
    expect(tracker.accept('Céu azul', allowRewind: true), isNull);
    expect(tracker.accept('Céu azul ilumina montanhas', allowRewind: true), 3);
    expect(tracker.accept('Céu azul ilumina montanhas distantes', allowRewind: true), 4);
  });
  test('repetição final atrasada não volta', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('Céu azul ilumina montanhas distantes. Nosso projeto começa nesta manhã tranquila.'));
    tracker.seek(9);
    expect(tracker.accept('Céu azul ilumina montanhas', isFinal: true, allowRewind: true), isNull);
    expect(tracker.index, 9);
  });
}
