# Especificação funcional — Oitosete FlowText v0.9.2

## Critério de aceite do modo Voz
1. O botão *Usar voz* aparece na primeira tela do app.
2. Ao tocar *Iniciar por voz*, o leitor abre em tela cheia e o microfone inicia.
3. O roteiro **não avança por velocidade de relógio nem pela energia do áudio**.
4. Uma transcrição alinhada a uma posição posterior **confirma uma única posição** (a última palavra lida); somente essa palavra recebe `#D1D93F` como fundo.
5. Após a última confirmação, o texto permanece onde parou até receber outra palavra alinhada. Hipóteses repetidas, silêncio e ruído não avançam.
6. A rolagem revela texto posterior mantendo o termo confirmado próximo da parte superior.
7. Ao navegar manualmente, a posição muda, mas não há destaque fictício.
8. O modo Velocidade continua contínuo e independente do modo Voz.

## Critérios de aceite da abertura e plataforma
0. O aplicativo aparece como **Oitosete FlowText** no launcher Android e no iPhone; ícone com fundo preto e logo original (somente símbolo).
1. Fundo preto e logo original SVG convertida a PNG após o launch nativo e durante o splash Flutter.
2. Cor principal do aplicativo `#D1D93F`.
3. Tela permanece acordada enquanto o leitor está ativo; libera wake lock ao sair.
4. Android gera APK de teste; iOS gera .app sem assinatura; ambos preservam permissões de câmera, microfone e rede local.
5. Controle remoto LAN usa PIN e exige autorização explícita para iniciar gravação remotamente.

## Limites
A atualização da palavra destacada depende do reconhecimento por streaming; atrasos de inferência e erros de palavras com 'lh' requerem testes em aparelho real. Somente a confirmação contextual permite avanço. O áudio da gravação continua independente do reconhecedor.
