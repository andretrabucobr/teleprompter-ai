import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/reading_navigation.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';

void main() {
  test('volta ao início do parágrafo e depois ao anterior', () {
    const text = 'Bom dia.\n\nHoje vamos gravar.\nTerceiro parágrafo.';
    final n = ReadingNavigation(text, ScriptMatcher.tokenize(text));
    expect(n.starts, [0, 2, 5]);
    expect(n.paragraph(4, -1), 2);
    expect(n.paragraph(2, -1), 0);
    expect(n.paragraph(0, -1), 0);
    expect(n.paragraph(2, 1), 5);
    expect(n.paragraph(5, 1), 5);
    expect(n.atOffset(text.indexOf('gravar')), 4);
  });
  test('roteiro vazio, acentos, espaços e CRLF', () {
    expect(ReadingNavigation('', []).paragraph(0, -1), 0);
    const text = 'Olá!\r\n   Próximo texto.';
    final n = ReadingNavigation(text, ScriptMatcher.tokenize(text));
    expect(n.starts, [0,1]);
    expect(n.atOffset(text.indexOf('Próximo')), 1);
    expect(n.atOffset(text.length), 2);
  });
}
