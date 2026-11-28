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
  test('regressão real build 26: título omitido e parciais crescentes', () {
    final t = ContextualScriptTracker('Bem-vindo ao Oitosete FlowText! Este texto pode acompanhar sua fala, ou avançar em velocidade fixa.');
    final partials = <String, int>{
      'Este texto': 5,
      'Este texto pode': 6,
      'Este texto pode acompanhar': 7,
      'Este texto pode acompanhar sua fala': 9,
      'Este texto pode acompanhar sua fala ou a': 10,
      'Este texto pode acompanhar sua fala ou avançar em': 12,
      'Este texto pode acompanhar sua fala ou avançar em velocidade': 13,
      'Este texto pode acompanhar sua fala ou avançar em velocidade fixa': 14,
    };
    for (final entry in partials.entries) {
      expect(t.accept(entry.key, isFinal: false).highlight, entry.value, reason: entry.key);
    }
    expect(t.accept(partials.keys.last, isFinal: true).confirmed, 14);
  });
  test('prefixo curto repetido não reposiciona sem desambiguação', () {
    final t = ContextualScriptTracker('Título principal este texto azul este texto verde');
    expect(t.accept('este texto', isFinal: false).highlight, -1);
    expect(t.accept('este texto verde', isFinal: false).highlight, 7);
  });
  test('omite palavras no meio após estabelecer âncora exata', () {
    final t = ContextualScriptTracker('hoje vamos agora apresentar nosso projeto');
    expect(t.accept('hoje apresentar nosso', isFinal: false).highlight, 4);
    expect(t.accept('hoje apresentar nosso projeto', isFinal: true).confirmed, 5);
  });
  test('prefixo inicial único aceita omissão de duas palavras', () {
    final t = ContextualScriptTracker('título principal este texto azul');
    expect(t.accept('este texto', isFinal: false).highlight, 3);
    expect(t.accept('este texto azul', isFinal: true).confirmed, 4);
  });
  test('log build 27: retomada do início com cursor no segundo parágrafo', () {
    final t = ContextualScriptTracker(
      'Olá bom dia Hoje eu vou falar com você sobre um novo projeto A ideia é simples',
      anchor: 12);
    expect(t.accept('Olá', isFinal: false).highlight, -1);
    expect(t.accept('Olá bom dia', isFinal: false).highlight, 2);
    expect(t.accept('Olá bom dia hoje eu vou', isFinal: false).highlight, 5);
    expect(t.accept('Olá bom dia hoje eu vou falar com você sobre um novo projeto', isFinal: false).highlight, 12);
    expect(t.accept('Olá bom dia hoje eu vou falar com você sobre um novo projeto', isFinal: true).confirmed, 12);
  });
  test('log build 27: uma substituição antes de número não paralisa o cursor', () {
    final t = ContextualScriptTracker('Temos 3 etapas e 25 minutos para apresentar a proposta');
    expect(t.accept('Temos três etapas de vinte e cinco minutos', isFinal: false).highlight, 5);
    expect(t.accept('Temos três etapas de vinte e cinco minutos para apresentar a proposta', isFinal: true).confirmed, 9);
  });
  test('log build 27: recupera após substituição de ler por olhar', () {
    final t = ContextualScriptTracker('Eu quero ler cada palavra com calma');
    expect(t.accept('Eu quero olhar cada palavra', isFinal: false).highlight, 4);
    expect(t.accept('Eu quero olhar cada palavra com calma', isFinal: true).confirmed, 6);
  });
  test('sem avanço por palavra fora de contexto', () {
    final t = ContextualScriptTracker('a casa fica bonita');
    expect(t.accept('bonita', isFinal: false).highlight, -1);
  });
}
