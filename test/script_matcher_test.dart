import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';

void main() {
  test('normaliza acentos portugueses', () {
    expect(ScriptMatcher.normalize('CÂMERA'), 'camera');
    expect(ScriptMatcher.normalize('gravação'), 'gravacao');
  });

  test('obtém a posição da última palavra reconhecida', () {
    final matcher = ScriptMatcher('Bom dia! Hoje vamos falar sobre o teleprompter.');
    final result = matcher.align('Bom dia hoje', -1);
    expect(result, isNotNull);
    expect(matcher.words[result!.index].normalized, 'hoje');
  });

  test('não move o roteiro com silêncio ou apenas uma palavra', () {
    final matcher = ScriptMatcher('A primeira frase e a segunda frase.');
    expect(matcher.align('', 2), isNull);
    expect(matcher.align('primeira', 2), isNull);
  });

  test('não retorna índice fora do texto', () {
    final matcher = ScriptMatcher('Teste simples de leitura.');
    final result = matcher.align('Teste simples de leitura', -1);
    expect(result, isNotNull);
    expect(result!.index, inInclusiveRange(0, matcher.words.length - 1));
  });

  test('LH: acompanha variantes ouvidas para lho, lha, lhi, lhu e lhe', () {
    final examples = <(String, String)>[
      ('Meu filho está aqui.', 'meu fio'),              // lho
      ('Minha filha chegou.', 'minha filia'),          // lha
      ('O olhinho fechou.', 'o oiinho'),                // lhi
      ('Um malhudo chegou.', 'um maiudo'),             // lhu
      ('A colher caiu.', 'a coier'),                   // lhe
      ('Eu trabalho todos os dias.', 'eu trabaio'),   // lho longo
      ('A folha verde caiu.', 'a foia'),              // lha reduzido
    ];
    for (final (script, spoken) in examples) {
      final match = ScriptMatcher(script).align(spoken, -1);
      expect(match, isNotNull, reason: '$script / $spoken');
      final verified = match!;
      expect(verified.index, 1, reason: '$script / $spoken');
      expect(verified.phoneticWords, 1, reason: '$script / $spoken');
      expect(verified.exactWords, 1, reason: '$script / $spoken');
    }
  });

  test('não confunde escolha e escola nem dá progresso por uma palavra', () {
    final matcher = ScriptMatcher('A escolha está correta.');
    expect(matcher.align('a escola', -1), isNull);
    expect(matcher.align('escoia', -1), isNull);
  });

  test('LH não permite salto arbitrário por duas palavras vagas', () {
    final matcher = ScriptMatcher(
        'Agora vamos conversar calmamente e lembrar que o meu filho chegou.');
    final match = matcher.align('meu fio', 0);
    expect(match, isNull);
  });
}
