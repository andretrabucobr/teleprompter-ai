# Teleprompter AI — MVP v0.4 (Android e iPhone)

**Estado:** código-fonte experimental; **NÃO é um APK/IPA instalado e validado**.
Requer Flutter e os SDKs da plataforma para compilar. O modelo Whisper não
acompanha este ZIP, porque ocupa centenas de MB.

> **Para compilar imediatamente no seu computador:** abra
> [`COMPILAR_LEIA_PRIMEIRO.md`](COMPILAR_LEIA_PRIMEIRO.md).
> No Windows, o arquivo `COMPILAR_ANDROID_WINDOWS.bat` conduz a compilação Android
> depois da instalação do Flutter SDK, Android SDK, JDK 17 e Python.
> A configuração nativa agora é **separada por plataforma**, sem exigir iOS no Windows.

## Novidades de reconhecimento da v0.4

- ASR offline Whisper multilíngue para português em **ambos** os modos (câmera
  integrada e leitor para câmera externa). No leitor externo, caso o modelo
  não esteja instalado/disponível, tenta `speech_to_text` nativo como fallback.
- Modelo **base INT8** padrão para maior precisão potencial; `tiny INT8` como
  alternativa mais leve. É necessário medir precisão e latência em cada aparelho;
  **base não garante menor atraso que tiny**.
- Um só microfone PCM16/16 kHz: câmera captura imagem sem áudio; o fluxo PCM
  alimenta Whisper e, quando há gravação, o WAV para mesclagem com o vídeo.
- Filtro de atividade de voz **por energia** (não um VAD neural): reduz chamadas
  do reconhecedor durante o silêncio, sem garantir rejeição de todo ruído.
- Janela recente de até **5 segundos**, tentativa de nova análise após **1,2 s**
  de áudio novo ou no fim de uma frase. **Isso não garante 1,2 s de latência**:
  inferência e carga do dispositivo também contam.
- Correspondência texto/roteiro por alinhamento flexível, com palavras omitidas,
  erros leves e interjeições, desambiguação por proximidade e dupla confirmação
  para saltos longos. Evita retrocesso automático; botão de retrocesso manual
  permite reler uma passagem.
- Pausar a rolagem durante uma gravação suspende o ASR, **não** o fluxo de áudio
  do vídeo. As duas formas de uso preservam o controle remoto por outro aparelho.

## Arquitetura

```text
                   Microfone (record, PCM16 16 kHz)
                               |
                       Stream PCM único
                      /                 \
  Captura WAV (se gravando)       Filtro de silêncio
            |                            |
  Faixa de som para MP4         Whisper base/tiny offline
            |                      (isolate próprio)
  Câmera (sem áudio)                   |
            |                  Transcrição em blocos
   Mesclagem nativa                         |
        (fallback)                   Alinhamento + estabilidade
            |                              |
       MP4 / WAV                      Texto segue a voz
```

No *leitor externo*, o PCM não é gravado em arquivo; é usado somente para
reconhecimento. As gravações locais ficam no diretório privado do aplicativo.

## Compilar Android (Windows, Linux ou macOS)

Requisitos: **Flutter 3.44+ / Dart 3.12+**, Android SDK e JDK 17.
O comando `flutter doctor -v` deve indicar que o ambiente Android está pronto.

```bash
# Dentro da pasta deste projeto:
flutter create --platforms=android .
python3 scripts/configurar_plataformas.py --platform android
python3 scripts/instalar_modelo.py --model base
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

O arquivo de saída será `build/app/outputs/flutter-apk/app-debug.apk`, **somente
se o build terminar sem erro**. O APK de teste não está assinado para publicação.
Para aparelhos com pouca memória, use `--model tiny` antes do build.

No Windows, pode ser necessário usar `python` em vez de `python3`. O download
do modelo usa a distribuição oficial do sherpa-onnx e requer acesso à Internet
ou `--archive CAMINHO_DO_ARQUIVO.tar.bz2` para um pacote já baixado.

## Compilar para iPhone (somente macOS com Xcode)

No Mac, execute `flutter create --platforms=ios .`,
`python3 scripts/configurar_plataformas.py --platform ios` e os demais
passos de instalação do modelo/testes antes de:

```bash
flutter build ios --release --no-codesign
```

Esse comando gera somente um **build iOS sem assinatura**, não um IPA instalável
em iPhone físico. Para instalar no aparelho, será preciso configurar assinatura
Apple, identificador do aplicativo e perfis de provisionamento no Xcode.

## Compilação automatizada no GitHub Actions

O repositório já contém `.github/workflows/build-mobile.yml`. Ao publicar este
projeto em um repositório GitHub, abra **Actions → Compilar Teleprompter AI →
Run workflow**, escolha `base` ou `tiny` e execute. O fluxo foi configurado para
início manual (evita builds automáticos e downloads grandes a cada commit).

O workflow está **preparado, não foi executado**. Caso passe, disponibilizará:
- APK Android de desenvolvimento;
- `Runner.app` iOS não assinado em ZIP (ainda requer assinatura para iPhone físico).

## Como testar a leitura

1. Instale o app nos dispositivos depois da compilação.
2. Na tela de edição, cole o roteiro e abra o leitor.
3. Selecione **Voz**. Fale as frases em português e observe a palavra destacada.
4. Teste pausas, frases repetidas, palavras puladas e leitura em velocidades
   diferentes. Os botões de avançar/voltar continuam disponíveis.
5. Para câmera integrada, selecione Câmera, conceda as permissões e grave.
6. Para outro celular como controle, use a função de pareamento por PIN/QR;
   mantenha ambos na mesma rede Wi-Fi confiável.

## Limites e bloqueios para publicação

- Whisper opera em **blocos sobrepostos**, não oferece streaming neural
  de baixa latência garantida. O desempenho em tempo real, a taxa de erro de
  palavras e a precisão das pausas **ainda não foram medidos**.
- O filtro de silêncio por energia pode confundir música, ruído e fala baixa.
  Antes da publicação, avaliar VAD neural e calibração adaptativa.
- WAV de 16 kHz, som e vídeo separados e mesclados posteriormente. A união
  em Media3/AVFoundation e o sincronismo labial **precisam de testes reais**.
- A junção de áudio pode falhar; o app procura preservar vídeo silencioso e
  WAV separadamente, sem prometer entrega sempre com som.
- Controle remoto `ws://` + PIN **sem criptografia**, adequado apenas à rede
  Wi-Fi confiável de teste. TLS, autenticação e testes de segurança necessários
  antes de disponibilizar o produto comercialmente.
- Testes unitários foram escritos; **não rodaram aqui**, porque o ambiente
  desta entrega não possui Flutter/Dart SDK nem Android SDK e não permite baixar
  os pacotes necessários. Não há build validado nesta entrega.

Mais detalhes em `docs/ESPECIFICACAO.md` e `docs/TESTES_DISPOSITIVOS.md`.
