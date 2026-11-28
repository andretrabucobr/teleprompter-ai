import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/asr_word_timing.dart';
import 'package:teleprompter_ai/core/contextual_script_tracker.dart';

void main() {
  test('reconstrói tokens SentencePiece em palavras temporizadas', () {
    final words = SentencePieceWordDecoder.decode(
      ['▁Bom', '▁di', 'a', '▁Oito', 'sete'],
      [0.10, 0.42, 0.48, 0.82, 0.90],
    );
    expect(words.map((word) => word.text).toList(), ['Bom', 'dia', 'Oit sete']);
    expect(words[0].startSeconds, 0.10);
    expect(words[1].startSeconds, 0.42);
    expect(words[1].endSeconds, 0.48);
    expect(words[1].tokenCount, 2);
  });

  test('preserva a ordem temporal em timestamps regressivos', () {
    final words = SentencePieceWordDecoder.decode(
      ['▁um', '▁dois', '▁três'], [0.2, 0.1, 0.3],
    );
    expect(words.map((word) => word.startSeconds).toList(), [0.2, 0.2, 0.3]);
  });

  test('alinha palavras reconhecidas e preserva os tempos', () {
    final tracker = ContextualScriptTracker('Bom dia hoje vamos gravar');
    final update = tracker.acceptTimedWords([
      const AsrWordTiming(text: 'Bom', startSeconds: 0.1, endSeconds: 0.2, tokenCount: 1),
      const AsrWordTiming(text: 'dia', startSeconds: 0.3, endSeconds: 0.4, tokenCount: 2),
      const AsrWordTiming(text: 'hoje', startSeconds: 0.5, endSeconds: 0.7, tokenCount: 1),
    ], isFinal: false);
    expect(update.state.display, 2);
    expect(update.matches.map((match) => match.index).toList(), [0, 1, 2]);
    expect(update.matches.map((match) => match.startSeconds).toList(), [0.1, 0.3, 0.5]);
    expect(update.state.confirmed, -1);
  });

  test('hipótese cumulativa não duplica o prefixo', () {
    final tracker = ContextualScriptTracker('A casa azul fica bonita');
    final first = tracker.acceptTimedWords([
      const AsrWordTiming(text: 'A', startSeconds: 0, endSeconds: .1, tokenCount: 1),
      const AsrWordTiming(text: 'casa', startSeconds: .2, endSeconds: .4, tokenCount: 1),
    ], isFinal: false);
    expect(first.matches.map((match) => match.index).toList(), [0, 1]);
    final revised = tracker.acceptTimedWords([
      const AsrWordTiming(text: 'A', startSeconds: 0, endSeconds: .1, tokenCount: 1),
      const AsrWordTiming(text: 'casa', startSeconds: .2, endSeconds: .4, tokenCount: 1),
      const AsrWordTiming(text: 'azul', startSeconds: .5, endSeconds: .7, tokenCount: 1),
    ], isFinal: false);
    expect(revised.matches.map((match) => match.index).toList(), [2]);
  });

  test('seek limpa o estado temporal da hipótese anterior', () {
    final tracker = ContextualScriptTracker('Bom dia hoje');
    tracker.acceptTimedWords([
      const AsrWordTiming(text: 'Bom', startSeconds: 0, endSeconds: .1, tokenCount: 1),
    ], isFinal: false);
    tracker.seek(-1);
    final update = tracker.acceptTimedWords([
      const AsrWordTiming(text: 'hoje', startSeconds: .2, endSeconds: .4, tokenCount: 1),
    ], isFinal: false);
    expect(update.state.display, -1);
  });
}
