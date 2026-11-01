# Especificação técnica — Teleprompter AI v0.4

## Objetivo

Acompanhar a posição do roteiro conforme a fala em português, com gravação
pela câmera do aplicativo ou uso como visor junto de câmera externa, e permitir
controle remoto com o mesmo aplicativo em outro Android/iPhone, por Wi-Fi.

## Módulos e responsabilidades

| Arquivo | Papel |
|---|---|
| `services/shared_audio_capture.dart` | Um microfone `record.startStream` PCM16 16 kHz mono; grava WAV apenas no modo Câmera e distribui PCM para ASR, se habilitado. |
| `core/speech_activity_gate.dart` | Filtro de energia por quadros de 20 ms; ignora silêncio para reduzir transcrição redundante. Não é VAD neural. |
| `services/whisper_asr_worker.dart` | Whisper multilíngue base/tiny em isolate, janelas até 5 s sobrepostas, tentativa de salto de 1,2 s e decodificação sem fila extensa. |
| `core/script_matcher.dart` | Alinhamento textual dinâmico, tolera omissões/fillers/erros leves e prioriza proximidade na sequência. |
| `core/speech_alignment_tracker.dart` | Histerese, anti-duplicata, movimento não regressivo e confirmação para saltos longos. |
| `services/speech_follow_service.dart` | Fallback nativo no leitor externo se ASR offline indisponível. |
| `services/wav_pcm_writer.dart` | Grava WAV sem manter áudio completo em RAM; recorta faixa por amostras. |
| `services/video_audio_composer.dart` | Tenta adicionar WAV ao vídeo silencioso e preservar arquivos caso falhe. |
| `screens/teleprompter_page.dart` | Leitor, câmera, controles e integração dos módulos. |
| `services/remote_session.dart` | Controle remoto experimental via WebSocket LAN/PIN/QR. |

## Estados

- `external/speed`: apenas leitor por velocidade, sem microfone.
- `external/voice`: PCM/Whisper offline sem WAV, fallback nativo em falha.
- `camera/speed`: PCM/WAV na gravação, leitor por velocidade.
- `camera/voice`: PCM dividido entre WAV e Whisper, sem abrir o microfone duas vezes.
- Ao pausar o texto durante a filmagem, o WAV continua; ao retomar, o ASR
  descarta a janela anterior para não usar transcrições antigas.

## Ajustes de precisão do MVP

1. **Whisper base INT8** é o modelo padrão para experimentação de qualidade.
   **Tiny INT8** reduz CPU e memória. O melhor depende do hardware e dos testes.
2. Reconhecimento após 1,2 s de áudio novo e também após fim de fala detectado.
   Inferência pode levar mais tempo, então não interpretar como prazo máximo.
3. Janela recente de 5 s, sem fila de decodificações; hipóteses antigas são
   descartadas após pausa/retomada da leitura.
4. Evita enviar silêncio para o ASR, reduzindo hallucinações em pausas.
5. Alinhador flexível aceita inserções, exclusões e pequenos erros de palavras.
6. Saltos pequenos com alto suporte podem avançar; saltos longos exigem duas
   hipóteses distintas e consistentes. Nenhuma hipótese move o texto para trás.
7. Reset ou avanço manual redefine a posição de referência do alinhador.

## Limitações e riscos técnicos

- **Não há prova de compilação:** falta SDK Flutter/Dart/Android no ambiente
  atual, sem acesso de rede para download. Workflow GitHub Actions incluído,
  mas ainda não executado.
- **Modelo não incluso:** executar instalador antes de compilar. A cópia local
  do modelo na primeira inicialização consome espaço no dispositivo.
- **VAD por energia:** não representa classificação robusta de fala humana;
  música e ruídos podem ativá-lo, e voz sussurrada pode ficar abaixo do limiar.
- **Gravação e áudio**: o corte PCM versus vídeo usa posição aproximada das
  amostras entre chamadas das APIs. Não há relógio nativo compartilhado;
  atraso/desvio A/V depende dos dispositivos e do muxer.
- **Amostragem:** 16 kHz é adequada à ASR e prova de conceito, não ideal para
  áudio profissional de vídeo. Futuro: áudio 48 kHz + reamostragem para ASR.
- **Rede:** PIN e ws:// em Wi-Fi confiável, sem criptografia. Necessário TLS
  e autenticação forte para distribuição pública.
- **Primeiro plano:** interrupções, chamadas telefônicas, travamento e segundo
  plano exigem testes reais para preservação dos arquivos.
- **Precisão:** nenhuma meta estatística de latência, WER ou falso avanço foi
  comprovada. Modelo base pode ser demasiado pesado em certos celulares.

## Critérios de aceite do reconhecimento (metas a validar)

- Português brasileiro: frases cotidianas, números, siglas, nomes próprios.
- Testar pelo menos 20 roteiros (curtos e longos), voz masculina/feminina,
  fala rápida/lenta, pausas e falas improvisadas. Anotar WER quando houver
  transcrição de referência.
- **Meta indicativa**, não medida: p50 de tempo fala→rolagem ≤ 1,5 s e p95
  ≤ 3 s nos aparelhos de referência; se não atingir, escolher modelo menor
  ou motor streaming realmente incremental.
- Nenhum salto durante 60 s de silêncio no ambiente de teste; menos de 1 salto
  indevido por 10 min de leitura em condições controladas (meta).
- Pausas não devem encerrar áudio de vídeo; gravação 10–30 min sem falha de PCM.
- Medir sincronismo de palmas em início/meio/fim e desvio A/V em ms.
- Testar Android→iOS e iOS→Android com comandos autorizados e rede interrompida.

**Status:** arquitetura e mudanças no código-fonte escritas; nenhuma dessas
metas foi validada em Android/iPhone físicos ou em compilação nesta entrega.
