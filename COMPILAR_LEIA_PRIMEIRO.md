# Compilar o Teleprompter AI (Android e iOS)

**Este ZIP contém código-fonte, não um APK pronto.** O aplicativo ainda não passou
por uma compilação Flutter real nem por testes físicos. O objetivo dos scripts é
executar a compilação no computador que já tem os SDKs necessários.

## 1. Android no Windows 10/11

Instale no computador (uma única vez):

1. **Flutter SDK** no canal estável, Flutter >= 3.44 (recomendado 3.50+):
   https://docs.flutter.dev/get-started/install
   Adicione `flutter\bin` ao `PATH` e abra um novo terminal.
2. **Android Studio**, incluindo Android SDK, Android SDK Platform Tools,
   Android SDK Command-line Tools e JDK 17:
   https://developer.android.com/studio
3. **Python 3.10+**: https://www.python.org/downloads/windows/
4. Conexão com a internet. O modelo de reconhecimento Whisper e os pacotes
   Flutter/Gradle são baixados durante a compilação. Reserve espaço em disco
   para as ferramentas e os modelos (vários gigabytes).

Abra PowerShell, execute `flutter doctor -v` e resolva o que estiver pendente.
Se necessário, execute `flutter doctor --android-licenses` e aceite as licenças.

**Para compilar:** extraia o ZIP (não execute dentro dele), abra a pasta
`teleprompter_ai_mvp` e dê dois cliques em **`COMPILAR_ANDROID_WINDOWS.bat`**.

O script:

- verifica Flutter, Java, Python e Android SDK;
- gera a estrutura Android (quando ausente);
- configura as permissões;
- baixa/instala o Whisper Base multilíngue INT8;
- executa `flutter pub get`, `flutter analyze` e `flutter test`;
- tenta compilar um APK de teste **Android ARM64**.

O APK, **apenas se todas as etapas terminarem sem erro**, ficará em:

`dist/TeleprompterAI-v0.4-debug-Android-arm64.apk`

É um APK de desenvolvimento. Não é uma versão publicada/assinada para a Play
Store. Para usar o modelo mais leve, execute em PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\compilar_android_windows.ps1 -Modelo tiny
```

Se o modelo já tiver sido baixado, também pode ser passado um arquivo oficial
`.tar.bz2` com `-ArquivoModelo 'C:\pasta\modelo.tar.bz2'`.

**Problemas frequentes:**

- `flutter não encontrado`: instale Flutter, adicione `flutter\bin` ao PATH e
  reabra o terminal.
- `Android SDK ausente`: configure SDK Manager no Android Studio e confira
  `ANDROID_SDK_ROOT`/`ANDROID_HOME`.
- `Licenças Android pendentes`: execute `flutter doctor --android-licenses`.
- `HTTP 403`/`timeout` ao baixar Whisper: teste a internet ou use o pacote
  oficial com `-ArquivoModelo`.
- `flutter analyze` ou `flutter test` falhou: o compilador parará e mostrará
  o motivo; envie o texto do erro para corrigirmos o código.
- `Gradle` falhou: confira JDK 17, Android SDK e a mensagem exata; evite
  apagar o cache inteiro sem identificar o erro.

## 2. Android em Linux ou Mac

Depois de instalar Flutter, Android SDK, JDK 17 e Python 3.10+:

```bash
cd teleprompter_ai_mvp
bash scripts/compilar_android_linux_macos.sh base
```

O APK aparece no diretório `dist/` se a compilação for bem-sucedida.

## 3. iOS no Mac com Xcode

**Não é possível compilar um aplicativo iOS instalável a partir de Windows.**
Em um Mac com Xcode, Flutter e Python, execute:

```bash
cd teleprompter_ai_mvp
bash scripts/compilar_ios_macos.sh base
```

O script gera `build/ios/iphoneos/Runner.app` **sem assinatura**. Para instalar
num iPhone físico, configure no Xcode o identificador do app, equipe Apple e
assinatura/provisionamento. Não existe `.ipa` pronto ou instalável neste ZIP.

## 4. Teste mínimo após instalar

No celular principal, abra **Câmera integrada** e conceda as permissões.
Teste primeiro o modo de rolagem por velocidade, depois **Voz**. Grave 20 a 30
segundos, faça uma pausa e retome; confirme que o texto avança e se o arquivo
exportado contém áudio sincronizado. Por fim, conecte o segundo aparelho na
mesma rede Wi-Fi e teste o PIN/QR Code.

**Limitações conhecidas:** o reconhecimento Whisper trabalha em janelas (não
streaming neural de latência garantida); câmera e áudio ainda não foram
validados em Android/iOS reais; o controle remoto usa `ws://` sem criptografia,
somente para uma rede Wi-Fi confiável. Consultar `docs/TESTES_DISPOSITIVOS.md`.
