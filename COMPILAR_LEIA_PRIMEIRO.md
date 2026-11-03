# Compilação online otimizada — Oitosete FlowText 0.9.4

Use o **GitHub Actions** para gerar um APK Android em release, ARM64. O fluxo foi atualizado para selecionar o reconhecimento e produzir um relatório real do tamanho do arquivo.

- Recomendação para manter a funcionalidade do streaming com fallback: `modelo=streaming`, `tipo_apk=release_arm64`.
- Para retirar apenas o Whisper Tiny adicional: `modelo=streaming_leve` (sem fallback se o Nemotron falhar).
- Para reduzir muito o modelo incluído: `modelo=base` (Whisper, transcrição em janelas; reconhecimento não tão responsivo).
- Para um APK de diagnóstico: `tipo_apk=debug` (maior).

O build utiliza o script de compatibilidade Media3 já validado em versões anteriores. A compilação release ainda precisa de validação em execução real.

O relatório `relatorio_tamanho_build.md` lista em MiB quanto o arquivo APK ocupa e suas categorias internas. O modelo incluído ainda é copiado para armazenamento local na primeira preparação; o relatório não mede espaço total no dispositivo.

**Build no Mac/Windows:** os scripts locais legados permanecem para testes de desenvolvimento com Flutter instalado. Para este perfil otimizado, use o GitHub Actions, que inclui a correção Media3 e o relatório.
