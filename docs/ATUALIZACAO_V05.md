# Teleprompter AI v0.5 — voz e tela cheia

## O que mudou

- **Iniciar** (rolagem por velocidade) abre a leitura em tela cheia imediatamente.
- Selecionar **Voz** começa o reconhecimento e abre a leitura em tela cheia;
  **Iniciar por voz** continua disponível para recomeçar após pausa.
- **Gravar** no modo câmera também abre a tela cheia e inicia a leitura.
- **Controle remoto → Iniciar** aciona o mesmo modo de tela cheia.
- Um toque na leitura exibe os botões **Pausar/Continuar**, **Voltar**, **Avançar**,
  **Sair da tela cheia** e **Gravar/Parar** quando a câmera está selecionada.
  Durante a reprodução os controles são ocultados após seis segundos.
- Ajustada a sensibilidade mínima do filtro de voz (RMS de 0,0055 para 0,0030),
  com manutenção de limiar relativo ao ruído estimado. São **ajustes heurísticos**;
  não equivalem a um detector neural de atividade vocal.
- Janela Whisper continua em 5 segundos, mas novas análises podem ocorrer após
  0,9 segundo de áudio novo (antes 1,2 segundo), desde que haja fala e o
  processador de inferência esteja disponível. Isso **não é uma latência garantida**.
- Alinhamento agora aceita duas palavras claras do começo do roteiro; saltos
  longos ainda exigem confirmação por mais de uma hipótese.
- Na sobreposição dos controles, informações **Microfone/Fala detectada** e
  **Ouvido** ajudam a distinguir entrada de áudio e reconhecimento de palavras.

## Compilar online

Preserve `.github/workflows/build-mobile.yml` (inclui a correção Media3
1.9.4 que já passou no Android). Atualize o código-fonte no repositório e abra:

Actions → Compilar Teleprompter AI (Android e iOS) → Run workflow → base.

O build Android disponibilizará `app-debug.apk` no artifact em caso de sucesso.
No iOS, o bundle continua não assinado.

## Testes reais essenciais

1. **Leitor externo / velocidade:** pressione Iniciar. A barra superior e os
   controles fixos devem desaparecer. Toque para ver controles, depois saia.
2. **Leitor externo / voz:** selecione Voz. Espere o carregamento do modelo e
   leia o roteiro em português. Ao tocar na tela, observe `Ouvido:`. Se a fala
   aparece correta mas o texto não avança, o problema é no alinhamento; se
   estiver incorreta ou ausente, é no microfone/modelo/VAD.
3. **Pausas/repetições:** faça uma pausa, repita parte da frase e fale mais
   rápido. O texto não deve saltar de parágrafo sem evidência suficiente.
4. **Câmera:** grave vídeo com a leitura em tela cheia. Confirme a captura de
   áudio, o sincronismo do arquivo exportado e o retorno dos controles.
5. **Controle remoto:** iniciar remotamente deve colocar a tela principal em
   tela cheia, mas não deve impedir uma pausa ou a saída local.

**Limites:** sem compilação/teste em dispositivo neste ambiente. Inferência
Whisper de blocos não é reconhecimento streaming nativo; modelos Base e Tiny
podem apresentar diferenças de qualidade e latência conforme o hardware.
No Android 16/API 36, a plataforma pode manter barras do sistema mesmo com
modo imersivo solicitado; o aplicativo continua ocultando a barra e controles
próprios. A qualidade da voz deve ser medida com gravações reais.
