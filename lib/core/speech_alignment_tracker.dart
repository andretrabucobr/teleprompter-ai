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
  bool _newUtterance = false;
  String? _lastCommittedHypothesis;

  int get index => _index;

  /// Usado após avanço/retrocesso manual; a pessoa pode reler outra passagem.
  void seek(int index) {
    _index = index.clamp(-1, matcher.words.length - 1).toInt();
    _pending = null;
    _pendingVotes = 0;
    _lastHypothesis = null;
    _lastWasFinal = false;
    _newUtterance = false;
    _lastCommittedHypothesis = null;
  }

  /// Retorna uma nova posição apenas quando o alinhamento é confiável.
  int? accept(String transcript, {bool isFinal = false, bool allowRewind = false,
      bool streamingPartials = false}) {
    final spoken = ScriptMatcher.tokenize(transcript);
    final normalized = spoken.map((word) => word.normalized).join(' ');
    final previous = _lastHypothesis;
    final previousWasFinal = _lastWasFinal;
    if (normalized.isEmpty) return null;
    // A hipótese final pode repetir exatamente a parcial; não a descartar,
    // porque o resultado final tem mais peso em saltos maiores.
    if (normalized == previous) {
      if (streamingPartials && isFinal && !previousWasFinal &&
          normalized == _lastCommittedHypothesis) {
        _lastWasFinal = true;
        _newUtterance = false;
        return null;
      }
      if ((!isFinal || previousWasFinal) &&
          !(streamingPartials && previousWasFinal && !isFinal)) return null;
    }
    if (previousWasFinal && !isFinal) {
      _newUtterance = true;
      if (streamingPartials) _lastCommittedHypothesis = null;
    }
    if (isFinal) _newUtterance = false;
    _lastHypothesis = normalized;
    _lastWasFinal = isFinal;
    // Se o streaming reconhece apenas UMA palavra, podemos acompanhar
    // somente quando ela é EXATAMENTE a próxima do roteiro. Não procurar
    // em outras regiões, evitando saltos e confusões com palavras parecidas.
    if (streamingPartials) {
      // O ASR envia uma hipótese cumulativa por fala. Aceite apenas a
      // extensão nova quando o prefixo termina no cursor conhecido.
      // Isso inclui palavras curtas, sem avançar por tempo ou som sozinho.
      final words = spoken.map((word) => word.normalized).toList();
      final committed = _lastCommittedHypothesis?.split(' ') ?? <String>[];
      final fresh = previous == null || (previousWasFinal && !isFinal);
      var start = -1;
      if (fresh || (_lastCommittedHypothesis == null && !_newUtterance)) {
        start = 0;
      } else if (committed.isNotEmpty && _index >= 0 &&
          committed.last == matcher.words[_index].normalized &&
          words.length >= committed.length) {
        var samePrefix = true;
        for (var i = 0; i < committed.length; i++) {
          if (committed[i] != words[i]) { samePrefix = false; break; }
        }
        if (samePrefix) start = committed.length;
      }
      if (start >= 0 && start < words.length) {
        var target = _index;
        var consumed = start;
        while (consumed < words.length && target + 1 < matcher.words.length &&
            matcher.words[target + 1].normalized == words[consumed]) {
          target++;
          consumed++;
        }
        // A palavra seguinte pode estar incompleta (ex.: "Bom di").
        // Confirme o prefixo exato agora, não espere a segunda palavra.
        // Se o restante contradiz o roteiro, mantenha o alinhador robusto.
        final incompleteTail = !isFinal && consumed == words.length - 1 &&
            target + 1 < matcher.words.length &&
            matcher.words[target + 1].normalized.startsWith(words[consumed]);
        if (target > _index && (consumed == words.length || incompleteTail)) {
          _newUtterance = false;
          final result = _commit(target);
          _lastCommittedHypothesis = words.take(consumed).join(' ');
          return result;
        }
      }
      // Uma revisão da mesma hipótese não é uma nova fala. Se ela não
      // acrescenta palavras ao prefixo já confirmado, não avance por repetição.
      if (!fresh && committed.isNotEmpty && words.length <= committed.length) {
        var samePrefix = true;
        for (var i = 0; i < words.length; i++) {
          if (committed[i] != words[i]) { samePrefix = false; break; }
        }
        if (samePrefix) return null;
      }
      // Hipótese final duplicada ou revisão sem extensão: não consuma
      // a próxima palavra repetida por engano.
      if (normalized == previous && !fresh && normalized == _lastCommittedHypothesis) {
        return null;
      }
    }
    if (spoken.length == 1 && spoken.single.normalized.length >= 3) {
      final adjacent = _index + 1;
      if (adjacent >= 0 && adjacent < matcher.words.length &&
          matcher.words[adjacent].normalized == spoken.single.normalized) {
        _newUtterance = false;
        return _commit(adjacent);
      }
    }
    // Caminho rápido: final da hipótese coincide exatamente com as duas
    // palavras em torno do cursor. Evita DP para cada parcial inequívoca.
    final adjacent = _index + 1;
    if (spoken.length >= 2 && _index >= 0 && adjacent < matcher.words.length &&
        spoken.last.normalized == matcher.words[adjacent].normalized &&
        spoken[spoken.length - 2].normalized == matcher.words[_index].normalized) {
      _newUtterance = false;
      return _commit(adjacent);
    }
    final match = matcher.align(transcript, _index, finalResult: isFinal);
    if (match == null || match.index <= _index) {
      // Somente nova hipótese parcial após endpoint do streaming, nunca
      // janela final do Whisper. Exige quatro palavras exatas e ocorrência única
      // na janela, sem candidato de avanço. Repetições ambíguas ficam manuais.
      if (allowRewind && _newUtterance && !isFinal && spoken.length >= 4 && matcher.words.length >= 4) {
        final tail = spoken.sublist(spoken.length - 4);
        final hits = <int>[];
        final lo = (_index - 120).clamp(3, matcher.words.length - 1).toInt();
        final hi = (_index + 35).clamp(0, matcher.words.length - 1).toInt();
        for (var end = lo; end <= hi; end++) {
          if (List.generate(4, (j) => matcher.words[end - 3 + j].normalized == tail[j].normalized).every((x) => x)) hits.add(end);
        }
        if (hits.length == 1 && hits.single < _index - 2) {
          _newUtterance = false;
          return _commit(hits.single);
        }
      }
      return null;
    }
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
    if (immediate) { _newUtterance = false; return _commit(match.index); }

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
    _lastCommittedHypothesis = _lastHypothesis;
    _pending = null;
    _pendingVotes = 0;
    return value;
  }
}
