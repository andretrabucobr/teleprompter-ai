# Subir v0.9.4 completa para o GitHub

1. Extraia o ZIP e envie **o conteúdo da pasta** para a raiz do repositório `andretrabucobr/teleprompter-ai`, incluindo `lib`, `scripts`, `test`, `assets`, `pubspec.yaml` e documentação.
2. Substitua arquivos de mesmo nome. Não envie pastas `android` ou `ios` geradas localmente; o workflow gera essas plataformas.
3. Se a pasta oculta `.github` não aparecer, edite `.github/workflows/build-mobile.yml` no navegador e copie integralmente o conteúdo de `WORKFLOW_GITHUB_COPIAR.txt`.
4. Abra **Actions → Oitosete FlowText 0.9.4 — Android e iOS → Run workflow**.
5. Para preservar a precisão de voz e gerar um APK mais enxuto, selecione `modelo=streaming` e `tipo_apk=release_arm64` (recomendação conservadora). Para diminuir também o tamanho do modelo de reserva, selecione `streaming_leve`, sabendo que não terá o Whisper de emergência.
6. Em `plataforma`, selecione `android` para gerar o APK. Após sucesso, baixe em **Artifacts** o APK e o `relatorio_tamanho_build.md`.

### Escolher o perfil certo

- **Celular Android recente:** `release_arm64` (um APK menor, apenas ARM64).
- **Compatibilidade com mais arquiteturas:** `release_todas` (gera vários APKs; cada aparelho usa o correspondente).
- **Diagnóstico de código:** `debug` (maior, não é uma estimativa de instalação final).
- **Menor instalador com voz local:** modelo `tiny` ou `base`; o acompanhamento perde a resposta incremental do Nemotron.
- **Streaming sem Whisper de reserva:** `streaming_leve`, mas pode não funcionar se o Nemotron não inicializar no aparelho.

**iPhone:** o workflow `ios` compila o app sem assinatura Apple. A instalação em iPhone real requer assinatura/provisionamento.

Não desinstale uma versão anterior sem salvar seus roteiros, especialmente ao trocar de debug para release.
