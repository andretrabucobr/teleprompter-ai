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
  });
}
