# v0.8 — Streaming real em português brasileiro

## O que mudou

- Entrada **única** `record` em PCM16 mono 16 kHz; a câmera permanece com `enableAudio:false`.
- Um mesmo chunk do microfone é gravado em WAV (quando há vídeo) e encaminhado
  ao `StreamingAsrWorker`, em um isolate dedicado.
- Blocos de **100 ms** são acumulados preservando bytes incompletos; o motor
  `sherpa_onnx.OnlineRecognizer` mantém contexto entre os blocos e emite
  **hipóteses parciais**. Ao detectar fim de frase, emite confirmação final.
- O alinhador do roteiro recebe as hipóteses parciais em tempo real;
  o cursor visual segue destacando as próximas palavras. Não fazemos
  avanço automático apenas por uma palavra isolada ou coincidência distante.
- `StreamingModelFiles.prepare()` copia o encoder para arquivo local em
  **partes de 8 MiB**, evitando carregar os ~627 MB de uma vez na RAM durante
  a primeira instalação. Depois utiliza o cache local.
- Fila PCM limitada a **3 s** para evitar crescimento ilimitado de memória
  se a inferência for mais lenta que a fala. Em sobrecarga, perde-se áudio
  somente para o ASR, nunca para o WAV da gravação.
- Se não houver modelo streaming no build, o fluxo Whisper anterior permanece.
  Se o Nemotron estiver presente mas falhar ao iniciar, tenta Whisper, que
  o workflow instala em versão Tiny como fallback.

## Modelo

- **Nemotron 3.5 ASR Streaming 0.6B INT8**, exportado pelo sherpa-onnx;
  variante **560 ms**, com idioma forçado **pt-BR** por stream.
- Arquivo de origem: `sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11.tar.bz2`.
- Arquivo compactado: aproximadamente **475 MB**; arquivos extraídos somam
  aproximadamente **650 MB**. A instalação e o APK de teste ocupam bastante
  espaço. Consulte os termos **NVIDIA OpenMDW 1.1** antes da distribuição.
- Script `scripts/instalar_streaming.py` verifica tamanho e SHA-256 fixado,
  extrai somente arquivos esperados, divide o encoder e escreve o manifesto.
- O modelo não está incluído no ZIP do código: é baixado pela CI para gerar
  o APK quando `modelo = streaming`.

## Compilação na nuvem

Edite `.github/workflows/build-mobile.yml` usando
`WORKFLOW_TELEPROMPTER_V08_STREAMING.txt` e execute no GitHub Actions com:

- `modelo = streaming`
- `plataforma = android` (ou `ios` / `ambos` quando necessário)

O workflow preserva a correção **Media3 1.9.4** e o patch
**idempotente** aplicado em `native_video_editor`.

Se a execução falhar na verificação de hash, **não ignore o erro**:
compare o SHA-256 com o arquivo oficial do modelo antes de atualizar.

## Testes obrigatórios em aparelho real

1. Iniciar por voz em tela cheia, confirmar que o rótulo mostra streaming pt-BR.
2. Falar `Meu filho olha a folha enquanto trabalho com a colher`;
   medir palavras incorretas e atraso do destaque.
3. Falar rápido, fazer uma pausa de 4 segundos e retomar.
4. Repetir uma frase que aparece em dois lugares do roteiro.
5. Gravar vídeo com câmera frontal e traseira enquanto o ASR está ligado;
   verificar vídeo, áudio, sincronismo labial, temperatura e memória.
6. Comparar `streaming` contra `base` no mesmo aparelho e roteiro.

**Ainda não validado em dispositivo**: tempo de inicialização, inferência sob
carga de vídeo e precisão pt-BR. 560 ms é o tamanho do trecho de contexto do
modelo — não uma garantia de latência total de 560 ms. O streaming reduz a
necessidade de esperar janelas de 5 s do Whisper, mas não antecipa o áudio.
