import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/contextual_script_tracker.dart';

void main() {
  test('primeira palavra curta e parcial revisável', () {
    final t = ContextualScriptTracker('A casa fica bonita');
    expect(t.accept('a', isFinal: false).highlight, 0);
    expect(t.state.confirmed, -1);
    expect(t.accept('a casa', isFinal: false).highlight, 1);
    expect(t.accept('a coisa', isFinal: false).highlight, 0);
    expect(t.accept('a casa', isFinal: true).confirmed, 1);
    expect(t.accept('fica', isFinal: false).highlight, 2);
  });
  test('final duplicada não consome repetição', () {
    final t = ContextualScriptTracker('vai vai agora');
    expect(t.accept('vai', isFinal: false).highlight, 0);
    expect(t.accept('vai', isFinal: true).confirmed, 0);
    expect(t.accept('vai', isFinal: true).confirmed, 0);
    expect(t.accept('vai', isFinal: false).highlight, 1);
  });
  test('número e sigla preservam posição visual', () {
    final t = ContextualScriptTracker('NR10 e 25');
    expect(t.accept('ene erre dez', isFinal: false).highlight, 0);
    expect(t.accept('ene erre dez e vinte e cinco', isFinal: true).confirmed, 2);
  });
  test('releitura inequívoca', () {
    final t = ContextualScriptTracker('céu azul ilumina montanhas distantes hoje vamos gravar', anchor: 7, highlight: 7);
    expect(t.accept('céu azul ilumina montanhas', isFinal: false).highlight, 3);
  });
  test('sem avanço por palavra fora de contexto', () {
    final t = ContextualScriptTracker('a casa fica bonita');
    expect(t.accept('bonita', isFinal: false).highlight, -1);
  });
}
