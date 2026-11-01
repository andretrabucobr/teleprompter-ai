/// Alinhamento aproximado entre uma transcrição curta e palavras do roteiro.
/// Não depende de Flutter, microfone, modelo ou conectividade.
class ScriptWord {
  const ScriptWord(this.text, this.normalized, this.start, this.end);

  final String text;
  final String normalized;
  final int start; // Offset UTF-16, compatível com TextSelection.
  final int end;
}

class ScriptMatch {
  const ScriptMatch({
    required this.index,
    required this.confidence,
    required this.matchedWords,
    required this.exactWords,
    this.phoneticWords = 0,
  });

  final int index;
  final double confidence;
  final int matchedWords;
  final int exactWords;
  /// Correspondências por pronúncia: lh → i/li/omissão, sempre com contexto.
  final int phoneticWords;
}

enum _WordRelation { different, phonetic, typo, exact }

class _PathScore {
  const _PathScore(this.score, this.matched, this.exact, this.phonetic);

  final double score;
  final int matched;
  final int exact;
  final int phonetic;

  _PathScore add(double points, {
    bool matchedWord = false,
    bool exactWord = false,
    bool phoneticWord = false,
  }) =>
      _PathScore(
        score + points,
        matched + (matchedWord ? 1 : 0),
        exact + (exactWord ? 1 : 0),
        phonetic + (phoneticWord ? 1 : 0),
      );
}

/// Busca *sufixos* da fala no roteiro, permitindo palavras omitidas,
/// interjeições e pequenos erros sem saltar entre frases parecidas.
class ScriptMatcher {
  ScriptMatcher(String script) : words = tokenize(script);

  final List<ScriptWord> words;

  static final RegExp _wordPattern = RegExp(
    r"[A-Za-zÀ-ÖØ-öø-ÿ0-9]+(?:['’-][A-Za-zÀ-ÖØ-öø-ÿ0-9]+)*",
  );

  static String normalize(String value) {
    var result = value.toLowerCase();
    const from = 'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ';
    const to = 'aaaaaaeeeeiiiiooooouuuucnyy';
    for (var i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result.replaceAll(RegExp('[^a-z0-9]'), '');
  }

  static List<ScriptWord> tokenize(String text) => [
        for (final match in _wordPattern.allMatches(text))
          if (normalize(match.group(0)!).isNotEmpty)
            ScriptWord(match.group(0)!, normalize(match.group(0)!),
                match.start, match.end),
      ];

  /// Erros de transcrição comuns com o dígrafo LH em português brasileiro.
  /// Não substitui o reconhecedor: serve apenas para alinhar a transcrição ao
  /// roteiro. Duas palavras com LH não se tornam automaticamente equivalentes.
  static bool _possibleLhPronunciation(String a, String b) {
    final hasLhA = a.contains('lh');
    final hasLhB = b.contains('lh');
    if (hasLhA == hasLhB) return false;
    final reference = hasLhA ? a : b;
    final heard = hasLhA ? b : a;
    if (reference.length < 4 || heard.length < 3) return false;
    // "filho" -> "filio" / "fio", "trabalho" -> "trabaio",
    // "folha" -> "folia" / "foia", "colher" -> "colier" / "coer".
    // A troca por apenas 'l' é excluída: confundiria "escolha" e "escola".
    return <String>['i', 'li', ''].any(
      (substitution) => reference.replaceAll('lh', substitution) == heard,
    );
  }

  static _WordRelation _relation(String a, String b) {
    if (a == b) return _WordRelation.exact;
    if (_possibleLhPronunciation(a, b)) return _WordRelation.phonetic;
    // "escolha" e "escola" diferem por uma letra, mas não são a mesma
    // palavra. Não aplicar distância de edição quando só um lado contém LH.
    if (a.contains('lh') != b.contains('lh')) {
      return _WordRelation.different;
    }
    if (_oneEditApart(a, b)) return _WordRelation.typo;
    return _WordRelation.different;
  }

  static bool _oneEditApart(String a, String b) {
    if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
      return false;
    }
    var i = 0;
    var j = 0;
    var errors = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
      } else {
        if (++errors > 1) return false;
        if (a.length > b.length) {
          i++;
        } else if (a.length < b.length) {
          j++;
        } else {
          i++;
          j++;
        }
      }
    }
    return errors + (a.length - i) + (b.length - j) <= 1;
  }

  /// Procura, primeiro, a partir da posição atual. Apenas uma transcrição
  /// final com forte evidência pode procurar em regiões mais distantes.
  ScriptMatch? align(String transcript, int previousIndex,
      {bool finalResult = false}) {
    if (words.isEmpty) return null;
    final speech = tokenize(transcript).map((w) => w.normalized).toList();
    if (speech.length < 2) return null;

    final lo = previousIndex < 0 ? 0 : (previousIndex - 2).clamp(0, words.length - 1).toInt();
    final hi = previousIndex < 0
        ? (words.length - 1).clamp(0, 90).toInt()
        : (previousIndex + 90).clamp(0, words.length - 1).toInt();
    final local = _search(speech, lo, hi, previousIndex);
    if (local != null) return local;
    if (finalResult && speech.length >= 5 && words.length > 90) {
      return _search(speech, 0, words.length - 1, previousIndex, global: true);
    }
    return null;
  }

  ScriptMatch? _search(List<String> speech, int first, int last, int previous,
      {bool global = false}) {
    ScriptMatch? best;
    var topScore = double.negativeInfinity;
    var nextScore = double.negativeInfinity;

    // O reconhecedor às vezes termina a frase com uma interjeição incorreta.
    // Uma palavra final pode ser descartada, mas não em frases muito curtas.
    final maxTailDrop = speech.length >= 4 ? 1 : 0;
    for (var dropped = 0; dropped <= maxTailDrop; dropped++) {
      final used = speech.sublist(
          (speech.length - dropped - 12).clamp(0, speech.length).toInt(),
          speech.length - dropped);
      if (used.length < 2) continue;
      for (var end = first; end <= last; end++) {
        if (_relation(used.last, words[end].normalized) ==
            _WordRelation.different) continue;
        if (previous >= 0 && end < previous) continue;
        final jump = previous < 0 ? end : end - previous;
        if (global && jump <= 80) continue; // Já pesquisado localmente.
        final alignment = _endingAt(used, end);
        if (alignment == null) continue;
        final matched = alignment.matched;
        final exact = alignment.exact;
        final phonetic = alignment.phonetic;
        final confidence = matched / (used.length + dropped);
        if (matched < (global ? 5 : 2)) continue;
        if (confidence < (global ? .84 : matched == 2 ? .85 : .64)) continue;
        // Duas palavras são suficientes com UMA troca LH quando a outra
        // é exata e a posição é muito próxima. Não aceita duas aproximações.
        if (matched == 2 && exact < 2 &&
            !(exact == 1 && phonetic == 1 && jump <= 5 && !global)) {
          continue;
        }
        if (jump > 18 && matched < 4) continue;
        if (jump > 50 && matched < 5) continue;
        if (global && exact < 4) continue;
        // Desempata trechos repetidos privilegiando o mais próximo.
        final score = confidence * 80 + matched * 3 + exact * 1.6 -
            jump * (global ? .05 : .24) - dropped * 4 - phonetic * 1.4;
        if (score > topScore) {
          // Duas variantes da MESMA posição não significam ambiguidade.
          if (best?.index != end) nextScore = topScore;
          topScore = score;
          best = ScriptMatch(index: end, confidence: confidence,
              matchedWords: matched, exactWords: exact,
              phoneticWords: phonetic);
        } else if (best?.index != end && score > nextScore) {
          nextScore = score;
        }
      }
    }
    // Se vários parágrafos distantes são igualmente possíveis, não adivinhar.
    if (global && topScore - nextScore < 2.5) return null;
    return best;
  }

  /// Programação dinâmica: inserção, omissão ou substituição custam pontos.
  /// A *última palavra falada* precisa corresponder à palavra de destino.
  /// As palavras do roteiro antes da primeira correspondente são opcionais.
  _PathScore? _endingAt(List<String> spoken, int end) {
    final start = (end - spoken.length - 4).clamp(0, words.length - 1).toInt();
    final candidates = words.sublist(start, end + 1);
    final m = spoken.length;
    final n = candidates.length;
    if (m < 2 || n < 2) return null;

    final table = List.generate(m, (_) => List<_PathScore>.filled(
        n, const _PathScore(double.negativeInfinity, 0, 0, 0)));
    for (var j = 0; j < n; j++) {
      table[0][j] = const _PathScore(0, 0, 0, 0);
    }
    for (var i = 1; i < m; i++) {
      table[i][0] = _PathScore(-i * 1.3, 0, 0, 0);
    }
    for (var i = 1; i < m; i++) {
      for (var j = 1; j < n; j++) {
        final relation = _relation(
          spoken[i - 1], candidates[j - 1].normalized);
        final diagonal = table[i - 1][j - 1].add(
          switch (relation) {
            _WordRelation.exact => 3.2,
            _WordRelation.typo => 2.0,
            _WordRelation.phonetic => 1.65,
            _WordRelation.different => -2.8,
          },
          matchedWord: relation != _WordRelation.different,
          exactWord: relation == _WordRelation.exact,
          phoneticWord: relation == _WordRelation.phonetic,
        );
        final withoutSpeech = table[i - 1][j].add(-1.3);
        final withoutScript = table[i][j - 1].add(-.95);
        var best = diagonal;
        if (withoutSpeech.score > best.score) best = withoutSpeech;
        if (withoutScript.score > best.score) best = withoutScript;
        table[i][j] = best;
      }
    }
    final lastRelation = _relation(spoken.last, candidates.last.normalized);
    if (lastRelation == _WordRelation.different) return null;
    return table[m - 1][n - 1].add(
      switch (lastRelation) {
        _WordRelation.exact => 3.2,
        _WordRelation.typo => 2.0,
        _WordRelation.phonetic => 1.65,
        _WordRelation.different => -2.8,
      },
      matchedWord: true,
      exactWord: lastRelation == _WordRelation.exact,
      phoneticWord: lastRelation == _WordRelation.phonetic,
    );
  }
}
