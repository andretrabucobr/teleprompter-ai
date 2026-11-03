# Revisão técnica — tamanho do Oitosete FlowText 0.9.4

## Escopo e achados no código-fonte

1. A v0.9.2 usava `flutter build apk --debug` por padrão. Isso inclui recursos de depuração e não reflete tamanho de distribuição.
2. O Nemotron Streaming é o maior componente do instalador: o encoder INT8 tem aproximadamente 627 MB sem compressão, além dos arquivos decoder e joiner. A cópia baixada pelo instalador do projeto tem aproximadamente 475 MB comprimidos (tamanho declarado no script; não baixado nesta auditoria).
3. O perfil `streaming` da v0.9.2 também incluía o Whisper Tiny, modelo adicional que aumenta o APK e a preparação inicial.
4. O carregador `StreamingModelFiles.prepare` monta os fragmentos do encoder no armazenamento interno. Essa cópia adiciona uso de disco, além do conteúdo do pacote.
5. Ícones, PNGs e código Dart são pequenos frente ao modelo, portanto comprimi-los teria impacto modesto. O ícone com margem 25% foi preservado.
6. A dependência `sherpa_onnx` possui componentes nativos que exigem validação por ABI. Não foi removido código nativo manualmente para evitar perda de compatibilidade.
7. A correção Kotlin do `native_video_editor` e as configurações de splash e identidade foram preservadas sem alteração funcional.

## Alterações aplicadas

- Build Android `release_arm64` como padrão (release e ABI ARM64); `release_todas` e `debug` ficam disponíveis.
- Perfil adicional `streaming_leve`, que elimina o Whisper Tiny de reserva **somente quando selecionado**.
- Modelo `streaming` padrão mantém a reserva e as funcionalidades existentes.
- Novo relatório de tamanho por categoria, publicado em `Artifacts` e no resumo do GitHub Actions.
- Retenção de artifacts limitada a 7 dias para reduzir acúmulo de arquivos grandes.
- Ícone v0.9.3 incorporado ao projeto completo.

## O que não foi feito

- Não foi reduzida a precisão do Nemotron por quantização adicional.
- Não foi alterada a lógica de voz, pausa, gravação e pareamento.
- Não foi implementado download sob demanda do modelo. Ele reduziria muito o download inicial do APK, mas exigiria conexão no primeiro uso, controle de integridade, retentativas e telas de progresso.
- Não foi medido o APK real porque Flutter/Android SDK não estão disponíveis no ambiente de autoria.

## Cuidados de distribuição

- `release_arm64` é indicado para aparelhos ARM64. Outros tipos de processador precisam de APK correspondente.
- A versão release gerada para testes não está configurada para assinatura de publicação na loja.
- Atualizações sobre o APK debug podem falhar por assinatura diferente: salve roteiros antes de desinstalar.
- APK e espaço de instalação são medidas diferentes. Além do modelo do pacote, a cópia para arquivos internos ocupa armazenamento adicional.

## Como medir ganho real

Execute **dois builds** com o mesmo `modelo`: um `debug` e um `release_arm64`; compare `relatorio_tamanho_build.md`. Para medir a retirada do modelo de reserva, compare `streaming` com `streaming_leve`, ambos `release_arm64`.

## Referências externas

- Flutter — https://docs.flutter.dev/perf/app-size
- Flutter — https://docs.flutter.dev/deployment/android
- Android — https://developer.android.com/topic/performance/reduce-apk-size
- Sherpa-ONNX — https://k2-fsa.github.io/sherpa/onnx/nemo/nemotron-streaming.html
