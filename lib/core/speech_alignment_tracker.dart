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

  int get index => _index;

  /// Usado após avanço/retrocesso manual; a pessoa pode reler outra passagem.
  void seek(int index) {
    _index = index.clamp(-1, matcher.words.length - 1).toInt();
    _pending = null;
    _pendingVotes = 0;
    _lastHypothesis = null;
  }

  /// Retorna uma nova posição apenas quando o alinhamento é confiável.
  int? accept(String transcript, {bool isFinal = false}) {
    final normalized = ScriptMatcher.tokenize(transcript)
        .map((word) => word.normalized).join(' ');
    if (normalized.isEmpty || normalized == _lastHypothesis) return null;
    _lastHypothesis = normalized;
    final match = matcher.align(transcript, _index, finalResult: isFinal);
    if (match == null || match.index <= _index) return null;
    final jump = _index < 0 ? match.index + 1 : match.index - _index;

    final immediate = (_index < 0 && match.matchedWords >= 3 &&
            match.confidence >= .76) ||
        (jump <= 12 && match.matchedWords >= 2 &&
            match.confidence >= .75) ||
        (jump <= 25 && match.matchedWords >= 4 &&
            match.confidence >= .82);
    if (immediate) {
      return _commit(match.index);
    }
    if (!isFinal || match.matchedWords < 5 || match.confidence < .84) {
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
