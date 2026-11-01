import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/predictive_reading_cursor.dart';

void main() {
  test('apresenta próximas palavras antes da primeira confirmação', () {
    final cursor = PredictiveReadingCursor(wordCount: 30);
    expect(cursor.focusIndex, 0);
    expect(cursor.focusEndIndex, 4);
    expect(cursor.tick(1000), 0);
    expect(cursor.tick(3000), 0); // silêncio não desloca
  });

  test('progride com fala e congela depois da pausa', () {
    final cursor = PredictiveReadingCursor(wordCount: 70);
    cursor.onSpeechActivity(true, 0);
    for (var now = 100; now <= 1000; now += 100) {
      cursor.tick(now);
    }
    expect(cursor.focusIndex, inInclusiveRange(2, 3));
    cursor.onSpeechActivity(false, 1000);
    final paused = cursor.focusIndex;
    expect(cursor.tick(3000), paused);
    expect(cursor.focusEndIndex, paused + 4);
  });

  test('a confirmação atrasada não move o foco durante o silêncio', () {
    final cursor = PredictiveReadingCursor(wordCount: 50);
    cursor.onSpeechActivity(true, 0);
    for (var now = 100; now <= 600; now += 100) {
      cursor.tick(now);
    }
    cursor.onSpeechActivity(false, 600);
    final frozen = cursor.focusIndex;
    cursor.onConfirmed(15, 1100); // resultado chegou depois da pausa
    expect(cursor.confirmedIndex, 15);
    expect(cursor.focusIndex, frozen);
    expect(cursor.tick(6000), frozen);
    cursor.onSpeechActivity(true, 6000);
    expect(cursor.tick(6100), frozen); // sem salto de 5 segundos
    for (var now = 6200; now <= 7100; now += 100) {
      cursor.tick(now);
    }
    expect(cursor.focusIndex, greaterThan(frozen));
  });

  test('alternar fala e pausa congela e retoma o cursor', () {
    final cursor = PredictiveReadingCursor(wordCount: 60);
    cursor.onSpeechActivity(true, 0);
    for (var now = 100; now <= 1000; now += 100) {
      cursor.tick(now);
    }
    cursor.onSpeechActivity(false, 1000);
    final stop = cursor.focusIndex;
    for (var now = 2000; now <= 10000; now += 1000) {
      expect(cursor.tick(now), stop);
    }
    cursor.onSpeechActivity(true, 10000);
    for (var now = 10100; now <= 11000; now += 100) {
      cursor.tick(now);
    }
    expect(cursor.focusIndex, greaterThan(stop));
  });

  test('nunca dispara sem confirmação do ASR', () {
    final cursor = PredictiveReadingCursor(
        wordCount: 200, maxUnconfirmedWords: 8);
    cursor.onSpeechActivity(true, 0);
    for (var now = 100; now <= 12000; now += 100) {
      cursor.tick(now);
    }
    expect(cursor.focusIndex, 8);
    expect(cursor.confirmedIndex, -1);
  });

  test('confirmação atrasada não joga o texto para trás', () {
    final cursor = PredictiveReadingCursor(wordCount: 80);
    cursor.onSpeechActivity(true, 0);
    for (var now = 100; now <= 1500; now += 100) {
      cursor.tick(now);
    }
    final before = cursor.focusIndex;
    cursor.onConfirmed(1, 1500);
    expect(cursor.focusIndex, greaterThanOrEqualTo(before));
    cursor.onConfirmed(0, 1700);
    expect(cursor.focusIndex, greaterThanOrEqualTo(before));
    cursor.onConfirmed(8, 2200);
    expect(cursor.focusIndex, 9);
  });

  test('ajusta faixa à frente sem modificar progresso', () {
    final cursor = PredictiveReadingCursor(wordCount: 20);
    cursor.onConfirmed(6, 1000);
    final current = cursor.focusIndex;
    cursor.setAnticipationWords(9);
    expect(cursor.focusIndex, current);
    expect(cursor.focusEndIndex, current + 8);
  });

  test('busca manual reposiciona e permite retorno', () {
    final cursor = PredictiveReadingCursor(wordCount: 20);
    cursor.onConfirmed(12, 100);
    cursor.seek(2);
    expect(cursor.focusIndex, 3);
    expect(cursor.confirmedIndex, 2);
    expect(cursor.tick(5000), 3);
  });

  test('roteiro vazio e final não produzem índice inválido', () {
    final empty = PredictiveReadingCursor(wordCount: 0);
    expect(empty.focusIndex, -1);
    expect(empty.focusEndIndex, -1);
    final one = PredictiveReadingCursor(wordCount: 1);
    expect(one.focusEndIndex, 0);
    one.onConfirmed(0, 100);
    expect(one.focusIndex, 0);
  });
}
