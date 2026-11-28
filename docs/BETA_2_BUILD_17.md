# Beta 2 — build 17: voz de baixa latência

- Modelo streaming_160 (novo padrão) e streaming_320 (alternativa para CPUs mais lentas); streaming e streaming_leve preservam 560 ms.
- Mesma família multilíngue Nemotron 3.5, variante oficial com tamanho e SHA256 fixados; manifesto e cache distinguem cada modelo.
- Resultados parciais emitidos a cada decode que altera a hipótese, sem aguardar fim da fila. Callback de captura solicita buffer menor.
- Alinhamento streaming permite avanço imediato por extensão exata, inclusive palavras curtas; duplicata final não avança palavra repetida.
- Indicador de fila de ASR acima de um segundo para diagnóstico. Limite anterior de três segundos mantido para não aumentar risco de perda de palavras.
- Testar S6 Lite e S22 Ultra com 160 e 320 ms; 560 ms permanece como referência. Blocos menores podem aumentar custo de inferência, portanto não há promessa de latência zero. Não há avanço por relógio no modo voz.
