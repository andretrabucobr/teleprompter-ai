# Teleprompter AI v0.6 — Tela ativa e LH no reconhecimento

## 1. Tela permanece ligada durante o teleprompter

- Novo plugin `wakelock_plus` para Android e iOS; não requer permissão extra.
- A tela não deve apagar automaticamente quando o roteiro estiver em tela cheia,
  lendo, gravando ou preparando esses recursos, desde que o app esteja em primeiro plano.
- Ao sair da leitura e interromper a reprodução/gravação, volta a respeitar
  o tempo de desligamento definido pelo usuário.
- Ao ir para segundo plano, o aplicativo libera o bloqueio de suspensão.
- O recurso não impede o bloqueio manual (botão lateral) nem mantém gravação
  funcionando com o aplicativo encerrado. A aplicação real depende do sistema.

## 2. Tratamento de pronúncias com LH

- Mantido o modelo de reconhecimento offline Whisper. A atualização **não altera
  o sinal de áudio nem garante que a transcrição exibida em “Ouvido” fique correta**.
- Adicionada correspondência contextual entre palavras do roteiro e variantes
  fonéticas que aparecem nas transcrições: “filho”/“filio”/“fio”,
  “trabalho”/“trabaio”, “folha”/“folia”/“foia”, “colher”/“coier”,
  “olhinho”/“oiinho” e “malhudo”/“maiudo”.
- O teleprompter exige outra palavra de referência correta para aceitar
  uma aproximação curta; impede saltos baseados apenas em duas palavras incertas.
- “escolha” e “escola” não são tratadas como equivalentes (proteção contra
  avanços incorretos).
- Comparação por palavras lidas funciona em português sem necessidade de
  configurar manualmente um glossário a cada roteiro.

## 3. Novo modelo opcional Whisper Small

- O instalador de modelos e o app também aceitam `small`, além de `base` e `tiny`.
- O fluxo GitHub Actions atualizado aceita `small` como opção do parâmetro
  `modelo`. **Padrão permanece `base`**.
- `small` pode melhorar erros reais de transcrição, mas exige mais memória,
  aumenta o APK e pode causar atraso na leitura em dispositivos menos potentes.
  É essencial testar a latência. Nenhum ganho é garantido sem comparar gravações.
- **NÃO atualize o `sherpa_onnx`** de forma indiscriminada: preserve a versão
  que já compilou para Android com a correção específica do Media3.

## Atualização no GitHub

1. Enviar os arquivos deste ZIP para a raiz do repositório, com as mesmas
   pastas `lib/`, `test/`, `scripts/`, `docs/` e o `pubspec.yaml`.
2. **Não é preciso alterar `.github`** para compilar com o modelo padrão `base`.
3. Em `Actions`, executar novamente a compilação com `base`.
4. Para testar `small`, editar no workflow existente somente a linha
   `options: [base, tiny]` para `options: [base, tiny, small]`, ou usar
   o arquivo de workflow opcional fornecido em separado.
5. O primeiro build serve para validar compatibilidade; só então instalar
   o APK em um Android real e testar o desempenho do reconhecimento.

## Testes no aparelho

1. Começar a leitura em tela cheia; deixar o celular parado por mais tempo
   do que seu período normal de apagamento; confirmar que continua aceso.
2. Pausar na tela cheia (sem sair): a tela deve continuar acesa.
3. Sair da tela cheia e parar a leitura: o bloqueio de suspensão deve ser liberado.
4. Ler, com fala natural, sem exagerar as sílabas: “Meu filho olha a folha;
   depois eu trabalho e pego a colher.”
5. Na sobreposição, tocar e verificar `Ouvido:`. Se as palavras aparecem
   trocadas mas o texto segue, a adaptação fonética funcionou; se a transcrição
   fica errada e a rolagem trava, testar `small` e comparar.
6. Fazer testes nas versões Android e iOS separadamente; aparelhos podem ter
   diferenças de desempenho, temperatura e consumo de bateria.

## Limites da entrega

- Foram feitas verificações de estrutura e testes lógicos simulados.
- O Flutter não está instalado no ambiente de produção deste pacote; não foram
  executados `flutter analyze`, `flutter test`, builds Android/iOS nem testes
  com áudio gravado em aparelhos reais.
