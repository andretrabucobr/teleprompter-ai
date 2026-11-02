# Oitosete FlowText — versão 0.9.2 consolidada

Aplicativo Flutter para **Android e iPhone**. Este pacote contém o projeto completo, não apenas diferenças em relação às versões anteriores. Integra as correções da v0.9.1 e a nova identidade visual v0.9.2.

## Identidade visual e nome de instalação

- **Nome exibido ao instalar:** `Oitosete FlowText`, configurado no AndroidManifest.xml e no Info.plist pelo script `scripts/configurar_plataformas.py` após `flutter create`.
- **Ícone:** logo Oitosete centralizada sobre fundo preto; PNGs nativos para Android (incluindo ícone adaptativo) e iOS em `scripts/icon_assets/`.
- **Abertura:** tela preta com logo original, tanto na abertura nativa (`scripts/configurar_splash.py`) quanto no Flutter.
- **Tema:** cor de destaque `#D1D93F` com fundo escuro.
- O identificador técnico do pacote Flutter permanece `teleprompter_ai`; renomeá-lo não é necessário para mudar o nome exibido no celular.

## Funcionalidades preservadas

1. **Voz:** a opção *Usar voz* está disponível ao abrir e é selecionada inicialmente; o microfone só inicia com o botão *Iniciar por voz*.
2. **Leitura por última palavra:** apenas a última palavra confirmada do roteiro recebe fundo `#D1D93F`. No modo Voz, o texto não avança por tempo ou só pela energia do áudio.
3. **Pausa ao deixar de falar:** no motor streaming/Whisper com detector de atividade, o silêncio cancela a rolagem e bloqueia deslocamentos originados de transcrições atrasadas. Uma correção tardia pode atualizar só o destaque, sem mover a tela.
4. **Tela cheia:** ao iniciar leitura ou voz; toque revela ou oculta controles. A tela permanece acesa durante a leitura.
5. **Câmera integrada, gravação e áudio compartilhado**, alternativa de uso com câmera externa e modo espelho.
6. **Controle remoto entre aparelhos** na mesma rede Wi-Fi (WebSocket com PIN).
7. **Streaming local em português**, com opção Whisper Base/Tiny/Small como alternativa.

A pausa rigorosa depende da disponibilidade do detector de atividade de voz no motor utilizado. No fallback nativo de transcrição, ela não é garantida. O reconhecimento e a gravação simultânea ainda exigem testes em dispositivos físicos, especialmente em aparelhos com menos RAM.

## Organização do código

- `lib/`: interface Flutter, alinhador de palavras, voz, gravação e controle remoto.
- `test/`: testes Dart incluídos nas etapas do CI.
- `assets/branding/`: logo da abertura e referência do ícone do aplicativo.
- `scripts/configurar_plataformas.py`: permissões, nome instalado e ícones nativos Android/iOS.
- `scripts/configurar_splash.py`: fundo preto e logo nas telas de lançamento.
- `scripts/icon_assets/`: todos os tamanhos de ícone para Android/iOS.
- `.github/workflows/build-mobile.yml`: compilação Android/iOS via GitHub Actions.
- `WORKFLOW_GITHUB_COPIAR.txt`: duplicata do workflow para edição manual pelo site do GitHub, caso a pasta oculta não seja enviada.

## Compilar pela internet

1. Extraia o ZIP e envie **o conteúdo das pastas** para a raiz do repositório, preservando `lib`, `test`, `assets`, `scripts` e `pubspec.yaml`.
2. Confira a presença de `scripts/configurar_splash.py`, `scripts/configurar_plataformas.py` e `scripts/icon_assets/` antes de executar.
3. Caso o GitHub não envie `.github`, substitua o conteúdo de `.github/workflows/build-mobile.yml` pelo de `WORKFLOW_GITHUB_COPIAR.txt`.
4. Abra **Actions → Oitosete FlowText 0.9.2 — Android e iOS → Run workflow**. Para Android escolha `plataforma=android`, `modelo=streaming`.
5. O APK de teste ficará na seção **Artifacts** *após o job concluir com sucesso*. A versão iOS produz um `.app` sem assinatura, que não pode ser instalado diretamente no iPhone sem assinatura Apple.

Não misture esta árvore de código com patches antigos. Antes de executar CI, remova do repositório arquivos legados que não fazem parte desta versão, especialmente testes antigos que podem ser executados automaticamente.

## Estado de validação

Os assets e scripts Python podem ser verificados localmente. **Não há Flutter/Android SDK/Xcode neste ambiente; portanto, esta versão ainda não foi compilada nem testada em aparelhos físicos.** É obrigatório validar a compilação e o nome/ícone exibidos no launcher do Android e do iPhone.
