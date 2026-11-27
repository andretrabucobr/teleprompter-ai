# Build 18 — primeira palavra

- Modelo oficial Nemotron multilíngue 80 ms, SHA256 e tamanho fixados; opções anteriores preservadas.
- PCM 20 ms, detecção de atividade em dois frames de voz (40 ms) no streaming, sem alterar VAD do Whisper.
- Alinhamento confirma prefixo exato mesmo quando última palavra está incompleta; não prevê palavra inexistente.
- Aceita resultados durante preparação do leitor e reseta hipótese antiga no início de sessão. Mantém pausa no silêncio.
- Status registra tempo entre início de voz detectado e primeira hipótese recebida (não latência ponta a ponta).
- Testar em S6 Lite/S22 Ultra: primeira palavra isolada, "Bom dia", "a casa", silêncio, retomada e gravação. Comparar 80 e 160 ms: menor bloco pode aumentar custo CPU; sem garantia de zero atraso.
