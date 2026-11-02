import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/confirmed_word_cursor.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/core/speech_alignment_tracker.dart';

void main() {
  test('sem palavras reconhecidas o cursor permanece parado', () {
    final cursor = ConfirmedWordCursor(wordCount: 15);
    expect(cursor.confirmedIndex, -1);
    expect(cursor.highlightedIndex, -1);
    expect(cursor.nextIndex, 0);
    // A ausência de hipóteses não exige timer: a posição não muda.
    expect(cursor.confirmedIndex, -1);
  });

  test('cada confirmação substitui o destaque; silêncio não avança', () {
    final cursor = ConfirmedWordCursor(wordCount: 9);
    expect(cursor.confirm(1), isTrue);
    expect(cursor.highlightedIndex, 1);
    expect(cursor.nextIndex, 2);
    expect(cursor.confirm(1), isFalse); // resultado parcial duplicado
    expect(cursor.confirm(0), isFalse); // transcrição antiga
    expect(cursor.confirmedIndex, 1);
    expect(cursor.highlightedIndex, 1);
    expect(cursor.confirm(2), isTrue);
    expect(cursor.highlightedIndex, 2);
  });

  test('busca manual não colore palavras não confirmadas', () {
    final cursor = ConfirmedWordCursor(wordCount: 20);
    cursor.confirm(6);
    cursor.seek(2);
    expect(cursor.confirmedIndex, 2);
    expect(cursor.highlightedIndex, -1);
    expect(cursor.nextIndex, 3);
    expect(cursor.confirm(3), isTrue);
    expect(cursor.highlightedIndex, 3);
  });

  test('resultado de streaming muda apenas na palavra alinhada', () {
    final matcher = ScriptMatcher('Bom dia hoje vamos apresentar o projeto.');
    final tracker = SpeechAlignmentTracker(matcher);
    final cursor = ConfirmedWordCursor(wordCount: matcher.words.length);
    expect(tracker.accept('Bom dia', isFinal: false), 1);
    expect(cursor.confirm(1), isTrue);
    expect(cursor.highlightedIndex, 1);
    expect(tracker.accept('', isFinal: false), isNull);
    expect(cursor.highlightedIndex, 1);
    expect(tracker.accept('Bom dia', isFinal: false), isNull);
    expect(cursor.highlightedIndex, 1);
    final next = tracker.accept('Bom dia hoje', isFinal: false);
    expect(next, 2);
    expect(cursor.confirm(next!), isTrue);
    expect(cursor.highlightedIndex, 2);
  });

  test('nenhum texto: sem índice de foco', () {
    final cursor = ConfirmedWordCursor(wordCount: 0);
    expect(cursor.nextIndex, -1);
    expect(cursor.confirm(0), isFalse);
  });
}
