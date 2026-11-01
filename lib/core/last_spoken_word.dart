/// Apenas a última palavra reconhecida pode receber a cor de destaque.
/// A posição preditiva serve somente para movimentar o roteiro na tela.
bool isLastSpokenWord({
  required int wordIndex,
  required int confirmedIndex,
  required bool voiceMode,
}) =>
    voiceMode && confirmedIndex >= 0 && wordIndex == confirmedIndex;
