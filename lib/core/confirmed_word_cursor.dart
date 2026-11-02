/// A posição avança exclusivamente quando uma palavra do roteiro é
/// confirmada pelo reconhecedor. A atividade do microfone, o tempo decorrido
/// e hipóteses não alinhadas NÃO movimentam o texto.
///
/// Depois de uma busca manual, o cursor usa a nova âncora, mas não pinta uma
/// palavra que ainda não foi reconhecida na sessão.
class ConfirmedWordCursor {
  ConfirmedWordCursor({required this.wordCount}) : assert(wordCount >= 0);

  final int wordCount;
  int _confirmedIndex = -1;
  int _highlightedIndex = -1;

  int get confirmedIndex => _confirmedIndex;
  int get highlightedIndex => _highlightedIndex;
  int get nextIndex => wordCount == 0
      ? -1
      : (_confirmedIndex + 1).clamp(0, wordCount - 1).toInt();

  /// Aceita somente a confirmação de uma palavra seguinte. Mesmo que a
  /// transcrição chegue depois do silêncio, ancora na última palavra lida;
  /// não existe qualquer avanço preditivo adicional.
  bool confirm(int index) {
    if (index < 0 || index >= wordCount || index <= _confirmedIndex) {
      return false;
    }
    _confirmedIndex = index;
    _highlightedIndex = index;
    return true;
  }

  /// Busca manual redefine o alinhamento, mas não marca como lida a palavra
  /// escolhida manualmente.
  void seek(int index) {
    _confirmedIndex = wordCount == 0
        ? -1
        : index.clamp(-1, wordCount - 1).toInt();
    _highlightedIndex = -1;
  }
}
