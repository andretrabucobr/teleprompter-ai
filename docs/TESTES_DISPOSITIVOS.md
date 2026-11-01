# Validação de reconhecimento e compilação — Teleprompter AI v0.4

Todos os cenários abaixo estão **pendentes de execução** até haver um build
Android/iOS validado e dispositivos reais.

| ID | Plataforma | Cenário | Resultado esperado | Estado |
|---|---|---|---|---|
| CI-01 | Android | Flutter analyze/test e build apk --debug | Saída verde e APK gerado | Pendente |
| CI-02 | macOS/iOS | Flutter analyze/test e build ios --no-codesign | Runner.app gerado | Pendente |
| ASR-01 | Ambos | 60s silêncio, voz pausada | Roteiro permanece parado | Pendente |
| ASR-02 | Ambos | Leitura normal de 2 min em PT-BR | Acompanha sem regressões | Pendente |
| ASR-03 | Ambos | Leitura lenta, pausas e fala rápida | Intervalos de atualização mensurados | Pendente |
| ASR-04 | Ambos | Repetir frase comum e pular palavras | Não salta ao parágrafo errado | Pendente |
| ASR-05 | Ambos | Pular parágrafo inteiro | Salta somente com evidência de frases | Pendente |
| ASR-06 | Ambos | Falar fora do roteiro e retomar | Ignora improviso e realinha | Pendente |
| ASR-07 | Ambos | Música ao fundo, barulho e voz baixa | Registrar falsos avanços e falsas pausas | Pendente |
| ASR-08 | Ambos | Modelo base versus tiny | Medir WER, p50/p95 da latência, CPU e aquecimento | Pendente |
| AV-01 | Android | Gravação câmera + voz 10 min | MP4 com áudio íntegro, sem microfone duplicado | Pendente |
| AV-02 | iOS | Gravação câmera + voz 10 min | Mesmo objetivo | Pendente |
| AV-03 | Ambos | Pausar/retomar texto gravando | Áudio continua sem interrupção | Pendente |
| AV-04 | Ambos | Palmas visíveis e audíveis no início/meio/fim | Medir sincronismo A/V em ms | Pendente |
| AV-05 | Ambos | Simular falha do editor nativo | Preservar MP4 e WAV separados | Pendente |
| AV-06 | Ambos | Gravar 30 min e interromper app | Medir consumo, salvar quando possível | Pendente |
| NET-01 | Android→iOS | Parear e controlar leitura/gravação | Comandos ACK, somente com autorização | Pendente |
| NET-02 | iOS→Android | Parear e controlar leitura/gravação | Mesmo comportamento | Pendente |
| NET-03 | Ambos | Desconectar Wi-Fi durante gravação | Gravação principal continua | Pendente |

### Captura de métricas

Para cada cenário, anotar: modelo do aparelho, OS, modelo ASR (base/tiny),
roteiro, duração, microfone, ruído, horário, CPU/memória se disponível, número
de avanços indevidos, deslocamento do texto e percepção de atraso. Para WER,
comparar a transcrição contra uma referência transcrita manualmente.

Para sincronismo labial: filmar palmas no início, meio e fim de uma gravação,
exportar o vídeo, medir diferença de tempo entre imagem das mãos se tocando e
pico da onda sonora. Comparar começo versus fim para detectar drift.
