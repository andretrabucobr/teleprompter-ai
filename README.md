# Oitosete FlowText — v0.10.0 (Beta 2 — Smart Seek e Remote Studio)

Projeto **completo** para Android e iOS. Este pacote incorpora a v0.9.2 consolidada, o ícone com 25% mais margem da atualização posterior e uma compilação Android otimizada.

## Novidades da Beta 2

- Fonte de 12 a 200 pontos lógicos, com persistência local.
- Smart Seek: repetir parágrafo, navegar com arraste, pressionar uma palavra e desfazer posicionamento. O cursor ASR é reancorado sem parar a gravação.
- Hipóteses parciais: caminho rápido para sequência exata adjacente, frames de 50 ms no streaming e destaque sem alterar o peso tipográfico. Retorno automático experimental limitado a nova fala streaming com contexto único.
- Remote Studio: abra o endereço HTTP exibido no pareamento no navegador; use o PIN. Monitor de texto sincronizado, seleção por palavra, rolagem, atalhos, ajustes e reconexão.
- Reposição de conexão nativa após desbloquear, reconexão com backoff e identificação por cliente. Apenas um operador por sessão.

Veja `docs/BETA_2_V0100.md` para critérios de teste e limitações.

## Funcionalidades preservadas

- Reconhecimento de fala por streaming em português, com Whisper como alternativa nos perfis que o incluem.
- Modo Voz disponível na entrada; tela cheia ao iniciar; tela permanece acesa durante a leitura.
- Destaque exclusivo da última palavra reconhecida na cor `#D1D93F`.
- Avanço por reconhecimento e pausa vinculada à fala conforme a lógica atual da v0.9.1; os dispositivos ainda precisam de validação.
- Gravação de vídeo e áudio compartilhado, modo espelho e controle remoto pela LAN.
- Splash preto com a logo e nome instalado **Oitosete FlowText**.
- Ícone preto com símbolo menor e maior margem no Android e iOS.

## Perfis do reconhecimento

| Perfil | Modelo no instalador | Vantagem | Limitação |
|---|---|---|---|
| `streaming` | Nemotron + Whisper Tiny | Preserva fallback da versão anterior | Arquivo grande |
| `streaming_leve` | Nemotron somente | Remove o tamanho do Whisper Tiny | Não há Whisper caso o streaming falhe |
| `base` | Whisper Base | Instalador consideravelmente menor que com Nemotron | Reconhecimento em janelas, não é streaming |
| `tiny` | Whisper Tiny | Menor modelo Whisper | Precisão inferior em algumas palavras |
| `small` | Whisper Small | Potencialmente mais precisão | Maior uso de CPU/RAM e arquivo maior |

**Não foi substituído nem comprimido novamente o Nemotron:** isso poderia prejudicar a precisão. A maior redução possível do instalador exige um modelo menor ou download do modelo sob demanda, o que requer uma nova implementação e testes.

## Compilação Android

A compilação online padrão agora usa `release_arm64`: APK de produção em modo release para celulares Android de 64 bits (ARM64), sem as ferramentas de depuração embutidas no APK debug. A opção `release_todas` gera APK separado por ABI; `debug` permanece disponível para diagnóstico.

O GitHub Actions cria `relatorio_tamanho_build.md` com tamanho do APK e categorias de componentes, e publica os valores no resumo da execução. O APK de release gerado pelo CI destina-se a **testes**; não confundir com assinatura de publicação na Play Store.

**Instalação sobre APK debug:** a assinatura pode não coincidir. Faça backup dos roteiros antes de desinstalar a versão anterior, pois dados locais podem ser apagados.

## Como atualizar o GitHub

Leia `COMO_ATUALIZAR_GITHUB.md`. Não misture arquivos de versões anteriores. O workflow está em `.github/workflows/build-mobile.yml`; cópia em `WORKFLOW_GITHUB_COPIAR.txt` caso o GitHub não aceite a pasta oculta.

## Estado da validação

A validação desta versão requer `flutter analyze`, `flutter test` e teste em dispositivos. **Flutter, Android SDK e Xcode não estavam disponíveis no ambiente de edição**; não houve compilação nem teste de hardware da v0.10.0. Os tamanhos finais devem ser obtidos no relatório do GitHub Actions.
