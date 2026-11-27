# Build 19 — reconhecimento inicial

- Confirma o prefixo exato do roteiro mesmo se a hipótese da palavra seguinte estiver errada. Não prevê palavras não reconhecidas.
- No streaming, a energia recente de um quadro permite testar a primeira hipótese adjacente antes de o VAD confirmar fala. O viewport só avança quando a fala for confirmada; silêncio continua protegido.
- Ao iniciar gravação por voz, prepara o cursor antes de abrir o microfone, evitando descartar hipóteses no início.
- Diagnóstico local: motor ativo, primeira hipótese bruta e primeiro destaque, tempos desde Iniciar (incluem a preparação), acessível tocando na tela. Sem gravação adicional de áudio ou envio de dados pelo diagnóstico.
- Alternativa experimental no modo Leitor externo: reconhecimento nativo solicitado onDevice, usando a dependência existente speech_to_text. Requer serviço/idioma local no aparelho; o SO pode reiniciar sessões de reconhecimento, e não há garantia de desempenho. Nemotron continua padrão, gravação usa PCM original.
- Testar a leitura isolada de "Bom", "A", "O", e depois frases completas. Comparar primeira hipótese e primeiro destaque no S6 Lite e S22 Ultra. Se a hipótese já chegar com várias palavras, o limite é o motor, não o destaque. Não prometer latência zero.
