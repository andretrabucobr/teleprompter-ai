# Beta 2 — build 16

- Modo voz: cinza para prefixo lido, última palavra confirmada em cor, restante branco.
- Diagnóstico limitado a 200 ms, não limita confirmação do cursor; animações de mesma linha não são reiniciadas. RepaintBoundary no leitor.
- Remote Studio: edição explícita com revisão, persistência local e bloqueio de salvamento durante leitura/gravação. Mudança de roteiro reinicia cursor.
- Android: porta preferencial 8765, anúncio mDNS local via JmDNS, nome normalmente flowtext.local; colisões, bloqueio de multicast e portas ocupadas podem mudar endereço. IP/QR alternativo; iOS mantém acesso por IP/porta fixa. Somente rede local confiável, sem TLS.
- Validar compilação, S6 Lite/S22 Ultra, reconexão, edição, gravação e resolução de nome em Mac/Windows. Não há medição de ganho real ainda.
