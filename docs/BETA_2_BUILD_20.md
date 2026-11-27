# Build 20 — seleção automática de voz

- Retira o seletor manual de motor. Android 12+ com reconhecedor local disponível: leitor externo tenta reconhecimento nativo em português com onDevice; se indisponível, usa ASR embarcado (Nemotron/Whisper). Em iOS, mantém motor embarcado.
- Fallback automático na inicialização e em falha permanente ou repetida do motor nativo; silêncio e ausência de correspondência não causam troca. Um motor por vez, sem disputa de microfone. Mantém cursor na troca. Não compara latência automaticamente e não garante que o motor escolhido seja mais rápido.
- Câmera mantém captura PCM compartilhada e não usa motor nativo concorrente. Sem dependência nova. Testar idioma local, modo avião, silêncio, pausa, falhas de serviço, gravação e posição do cursor. Verificar disponibilidade e desempenho real no S6 Lite/S22 Ultra.
