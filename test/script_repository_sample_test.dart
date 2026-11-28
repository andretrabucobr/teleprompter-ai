import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/services/script_repository.dart';

void main() {
  test('substitui somente o exemplo legado intacto', () {
    const old = 'Bem-vindo ao Oitosete FlowText!\n\n'
        'Este texto pode acompanhar sua fala, ou avançar em velocidade fixa.\n\n'
        'Para gravar na câmera do aplicativo, selecione Câmera.\n\n'
        'Para controlar de outro celular, abra Controle remoto nos dois aparelhos.';
    expect(ScriptRepository.resolveSavedScript(old), ScriptRepository.sample);
    expect(ScriptRepository.resolveSavedScript('$old\nMeu conteúdo'), '$old\nMeu conteúdo');
    expect(ScriptRepository.resolveSavedScript('Meu roteiro'), 'Meu roteiro');
    expect(ScriptRepository.resolveSavedScript(ScriptRepository.sample), ScriptRepository.sample);
    expect(ScriptRepository.resolveSavedScript('Olá, bom dia! Hoje eu vou falar com você sobre um novo projeto.\n\nA ideia é simples. Eu quero ler cada palavra com calma e seguir o texto no meu próprio ritmo.\n\nAgora vamos fazer uma pequena pausa. Muito bem, podemos continuar. O trabalho de hoje começa aqui.\n\nTemos 3 etapas e 25 minutos para apresentar a proposta. A tecnologia de IA pode ajudar a nossa equipe.\n\nVamos voltar a um ponto importante. A ideia é simples. Eu quero ler cada palavra com calma.\n\nPor fim, agradeço a sua atenção. Até a próxima!'), ScriptRepository.sample);
  });
}
