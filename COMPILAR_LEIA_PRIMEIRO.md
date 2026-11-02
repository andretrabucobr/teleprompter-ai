# Oitosete FlowText v0.9.2 — compilação

## Na nuvem, usando GitHub Actions

- Envie o **projeto inteiro** para a raiz do repositório. Verifique `scripts/`, `lib/`, `assets/`, `test/` e `pubspec.yaml`.
- Confira especificamente `scripts/configurar_splash.py`, `scripts/configurar_plataformas.py` e a pasta `scripts/icon_assets/`.
- O workflow nativo está em `.github/workflows/build-mobile.yml`. Se o upload ignorar a pasta oculta, copie `WORKFLOW_GITHUB_COPIAR.txt` para o arquivo de workflow pelo editor do GitHub.
- Escolha `modelo=streaming`, `plataforma=android`, e execute **Oitosete FlowText 0.9.2 — Android e iOS**.
- O workflow gera arquivos nativos temporários com `flutter create`, configura o nome instalado, o ícone e a abertura, instala o modelo, analisa o código, roda testes e tenta gerar o APK.
- Após sucesso, baixe o APK na seção Artifacts. Para iPhone, o aplicativo fica sem assinatura Apple.

## No Mac (opcional)

Use `bash scripts/compilar_android_linux_macos.sh base` para Android com Whisper Base ou `bash scripts/compilar_ios_macos.sh base` para iOS não assinado. É necessário ter os SDKs locais. Para o modelo streaming, use o workflow na nuvem, que inclui a instalação do modelo streaming e fallback.

**Validação:** somente testes estáticos e de configuração nativa foram executados neste ambiente; a compilação Flutter real depende do CI ou dos SDKs locais.
