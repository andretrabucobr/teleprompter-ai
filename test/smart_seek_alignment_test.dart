import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/core/speech_alignment_tracker.dart';

void main() {
  test('streaming confirma imediatamente palavras curtas e repetidas', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('A casa de um amigo é bonita.'));
    expect(tracker.accept('A', streamingPartials: true), 0);
    expect(tracker.accept('A casa', streamingPartials: true), 1);
    expect(tracker.accept('A casa de', streamingPartials: true), 2);
    expect(tracker.accept('A casa de um', streamingPartials: true), 3);
    expect(tracker.accept('A casa de um amigo é', streamingPartials: true), 5);
    expect(tracker.accept('A casa de um amigo é', streamingPartials: true, isFinal: true), isNull);
    expect(tracker.accept('bonita', streamingPartials: true), 6);
  });
  test('final duplicado não consome palavra repetida do roteiro', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('Vai vai agora.'));
    expect(tracker.accept('Vai', streamingPartials: true), 0);
    expect(tracker.accept('Vai', streamingPartials: true, isFinal: true), isNull);
    expect(tracker.index, 0);
    expect(tracker.accept('Vai', streamingPartials: true), 1);
    expect(tracker.accept('Vai agora', streamingPartials: true), 2);
  });
  test('parcial sem correspondência não pula pela palavra isolada', () {
    final tracker = SpeechAlignmentTracker(ScriptMatcher('A casa de um amigo.'));
    expect(tracker.accept('Amigo', streamingPartials: true), isNull);
    expect(tracker.index, -1);
  });
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
