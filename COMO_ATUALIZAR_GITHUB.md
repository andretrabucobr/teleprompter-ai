# Atualização completa do repositório para Oitosete FlowText v0.9.2

Este ZIP é uma **versão completa**; não adicione novos patches de versões antigas.

1. Extraia o arquivo e coloque os itens de sua raiz diretamente na raiz do repositório `andretrabucobr/teleprompter-ai`. O GitHub deve mostrar `lib/`, `scripts/`, `assets/`, `test/`, `pubspec.yaml`.
2. Substitua os arquivos de mesmo nome. Para uma substituição realmente limpa, exclua do repositório arquivos antigos que não estão neste ZIP, como `lib/core/predictive_reading_cursor.dart` e `test/predictive_reading_cursor_test.dart`, se existirem.
3. Confirme na branch principal os arquivos `scripts/configurar_plataformas.py`, `scripts/configurar_splash.py` e a pasta `scripts/icon_assets/` (não deixe a pasta inteira do projeto dentro de outra pasta).
4. Se a pasta oculta `.github/` não aparecer no upload, abra `.github/workflows/build-mobile.yml`, clique em editar e cole integralmente o conteúdo de `WORKFLOW_GITHUB_COPIAR.txt`.
5. Em GitHub Actions, execute **Oitosete FlowText 0.9.2 — Android e iOS**, opção `modelo=streaming` e `plataforma=android`.
6. Após o job verde, baixe o APK em **Artifacts**, instale e confira que o nome mostrado é `Oitosete FlowText` e que o ícone tem fundo preto e o símbolo da logo.

**iPhone:** o job iOS gera um aplicativo sem assinatura; requer assinatura Apple e provisionamento para instalação/TestFlight. O texto do nome pode aparecer abreviado no launcher conforme o tamanho da tela.

**Observação:** em atualizações de APK no Android, o sistema pode manter o ícone antigo em cache; confirme inicialmente na tela de informações do aplicativo ou reinicie o launcher, se necessário.

**Atenção ao atualizar APKs de teste:** builds `--debug` de execuções diferentes podem ser assinados com chaves de debug diferentes. Se a instalação sobre a versão antiga for recusada, faça backup dos roteiros antes de desinstalar a versão anterior; a desinstalação normalmente apaga os dados locais do aplicativo.
