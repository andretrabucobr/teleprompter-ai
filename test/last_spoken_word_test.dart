import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/app_colors.dart';
import 'package:teleprompter_ai/core/last_spoken_word.dart';
import 'package:flutter/material.dart';

void main() {
  test('apenas a última palavra confirmada é marcada', () {
    final highlights = List<bool>.generate(12, (index) => isLastSpokenWord(
      wordIndex: index,
      confirmedIndex: 4,
      voiceMode: true,
    ));
    expect(highlights.where((value) => value), hasLength(1));
    expect(highlights[4], isTrue);
    expect(highlights[5], isFalse); // previsão não gera destaque
    expect(highlights[3], isFalse); // palavras anteriores não ficam marcadas
  });

  test('antes da primeira palavra não existe destaque', () {
    expect(isLastSpokenWord(
      wordIndex: 0,
      confirmedIndex: -1,
      voiceMode: true,
    ), isFalse);
  });

  test('modo por velocidade não usa cor de reconhecimento', () {
    expect(isLastSpokenWord(
      wordIndex: 2,
      confirmedIndex: 2,
      voiceMode: false,
    ), isFalse);
  });

  test('a cor de marca é exatamente #D1D93F', () {
    expect(AppColors.brand, const Color(0xFFD1D93F));
  });
}
