import 'script_matcher.dart';

/// Decide quando uma hipótese de ASR já é suficiente para mover o texto.
/// Ignora silêncio, duplicatas e regressões. Saltos longos exigem confirmação.
class SpeechAlignmentTracker {
  SpeechAlignmentTracker(this.matcher, {int initialIndex = -1})
      : _index = initialIndex;

  final ScriptMatcher matcher;
  int _index;
  int? _pending;
  int _pendingVotes = 0;
  String? _lastHypothesis;
  bool _lastWasFinal = false;

  int get index => _index;

  /// Usado após avanço/retrocesso manual; a pessoa pode reler outra passagem.
  void seek(int index) {
    _index = index.clamp(-1, matcher.words.length - 1).toInt();
    _pending = null;
    _pendingVotes = 0;
    _lastHypothesis = null;
    _lastWasFinal = false;
  }

  /// Retorna uma nova posição apenas quando o alinhamento é confiável.
  int? accept(String transcript, {bool isFinal = false}) {
    final normalized = ScriptMatcher.tokenize(transcript)
        .map((word) => word.normalized).join(' ');
    if (normalized.isEmpty) return null;
    // A hipótese final pode repetir exatamente a parcial; não a descartar,
    // porque o resultado final tem mais peso em saltos maiores.
    if (normalized == _lastHypothesis && (!isFinal || _lastWasFinal)) {
      return null;
    }
    _lastHypothesis = normalized;
    _lastWasFinal = isFinal;
    // Se o streaming reconhece apenas UMA palavra, podemos acompanhar
    // somente quando ela é EXATAMENTE a próxima do roteiro. Não procurar
    // em outras regiões, evitando saltos e confusões com palavras parecidas.
    final spoken = ScriptMatcher.tokenize(transcript);
    if (spoken.length == 1 && spoken.single.normalized.length >= 4) {
      final adjacent = _index + 1;
      if (adjacent >= 0 && adjacent < matcher.words.length &&
          matcher.words[adjacent].normalized == spoken.single.normalized) {
        return _commit(adjacent);
      }
    }
    final match = matcher.align(transcript, _index, finalResult: isFinal);
    if (match == null || match.index <= _index) return null;
    final jump = _index < 0 ? match.index + 1 : match.index - _index;

    // Duas palavras inequívocas já bastam para seguir frases curtas no
    // início. Nas demais situações, exige mais evidência conforme o salto.
    // Evita travar até o terceiro/quarto termo em "Bom dia" ou "Olá pessoal".
    // Ex.: "meu fio" ouvido para "meu filho" no roteiro. Só avança com
    // outra palavra EXATA como âncora e deslocamento de no máximo 5 palavras.
    final shortLhMatch = jump <= 5 && match.matchedWords == 2 &&
        match.exactWords == 1 && match.phoneticWords == 1 &&
        match.confidence >= .95;
    final immediate = shortLhMatch || (_index < 0
        ? (jump <= 8 && match.matchedWords >= 2 &&
                match.exactWords >= 2 && match.confidence >= .95) ||
            (jump <= 24 && match.matchedWords >= 3 &&
                match.exactWords >= 2 && match.confidence >= .76)
        : (jump <= 8 && match.matchedWords >= 2 &&
                match.exactWords >= 1 && match.confidence >= .84) ||
            (jump <= 16 && match.matchedWords >= 3 &&
                match.exactWords >= 2 && match.confidence >= .78) ||
            (jump <= 25 && match.matchedWords >= 4 &&
                match.exactWords >= 3 && match.confidence >= .82));
    if (immediate) return _commit(match.index);

    // Nunca avançar grandes trechos apenas por uma palavra repetida ou uma
    // transcrição instável. São necessárias duas janelas finais compatíveis.
    if (!isFinal || match.matchedWords < 4 ||
        match.exactWords < 3 || match.confidence < .84) {
      return null;
    }
    if (_pending != null && (match.index - _pending!).abs() <= 5) {
      _pendingVotes++;
    } else {
      _pending = match.index;
      _pendingVotes = 1;
    }
    // Duas hipóteses distintas e compatíveis precisam confirmar um salto.
    if (_pendingVotes >= 2) return _commit(match.index);
    return null;
  }

  int _commit(int value) {
    _index = value;
    _pending = null;
    _pendingVotes = 0;
    return value;
  }
}
