import 'dart:math' as math;

/// Cursor visual de leitura, separado da última palavra confirmada pelo ASR.
///
/// A transcrição é retrospectiva: não pode dizer o que será falado.
/// Em vez disso, a leitura progride suavemente APENAS enquanto o microfone
/// identifica atividade de voz, com limite de distância à última âncora
/// confirmada. Destaca-se uma faixa de palavras seguintes, não uma
/// transcrição inventada. Relógio injetável permite testes determinísticos.
class PredictiveReadingCursor {
  PredictiveReadingCursor({
    required this.wordCount,
    int anticipationWords = 5,
    int maxUnconfirmedWords = 10,
    double initialWordsPerSecond = 2.6,
  })  : assert(wordCount >= 0),
        assert(anticipationWords >= 1),
        assert(maxUnconfirmedWords > 0),
        _anticipationWords = anticipationWords,
        _maxUnconfirmedWords = maxUnconfirmedWords,
        _wordsPerSecond = initialWordsPerSecond;

  final int wordCount;
  final int _maxUnconfirmedWords;
  int _anticipationWords;
  double _wordsPerSecond;
  double _estimatedPosition = 0;
  int _confirmedIndex = -1;
  int? _lastTickMillis;
  int? _lastConfirmationMillis;
  int _lastConfirmationIndex = -1;
  bool _speechActive = false;

  int get confirmedIndex => _confirmedIndex;
  int get anticipationWords => _anticipationWords;
  bool get speechActive => _speechActive;
  double get estimatedWordsPerSecond => _wordsPerSecond;

  /// Primeiro termo da faixa em destaque; antes da primeira fala começa em 0.
  int get focusIndex => wordCount == 0
      ? -1
      : _estimatedPosition.floor().clamp(0, wordCount - 1).toInt();

  /// Último termo destacado para o leitor ler em seguida (inclusivo).
  int get focusEndIndex => wordCount == 0
      ? -1
      : (focusIndex + _anticipationWords - 1)
          .clamp(0, wordCount - 1).toInt();

  void setAnticipationWords(int value) {
    _anticipationWords = value.clamp(1, 12).toInt();
  }

  /// Atualiza a previsão a partir da atividade de voz medida em PCM.
  /// Quando o silêncio começa, o progresso para; não há rolagem por tempo
  /// decorrido durante a pausa.
  void onSpeechActivity(bool speaking, int nowMillis) {
    // A transição para silêncio não integra tempo adicional: congela
    // imediatamente a posição. Breves intervalos entre sílabas já são
    // filtrados pelo detector PCM antes de chegar até aqui.
    if (!speaking) {
      _speechActive = false;
      _lastTickMillis = nowMillis;
      return;
    }
    if (!_speechActive) {
      _speechActive = true;
      _lastTickMillis = nowMillis; // retoma sem somar o período em silêncio
    }
  }

  /// Confirmação atrasada do reconhecedor. Nunca faz o foco voltar.
  /// Ajusta a velocidade estimada apenas com pares de posições confiáveis.
  void onConfirmed(int index, int nowMillis) {
    tick(nowMillis);
    if (index < 0 || index >= wordCount || index <= _confirmedIndex) return;
    if (_lastConfirmationMillis != null &&
        _lastConfirmationIndex >= 0) {
      final duration = nowMillis - _lastConfirmationMillis!;
      final advances = index - _lastConfirmationIndex;
      if (duration >= 450 && duration <= 6000 && advances > 0 && advances <= 16) {
        final measured = (advances * 1000.0 / duration)
            .clamp(1.2, 4.5).toDouble();
        _wordsPerSecond = _wordsPerSecond * .75 + measured * .25;
      }
    }
    _lastConfirmationMillis = nowMillis;
    _lastConfirmationIndex = index;
    _confirmedIndex = index;
    // O ASR pode confirmar palavras vários instantes após a pessoa parar.
    // Registra a confirmação para o próximo trecho, mas não movimenta a
    // área de leitura enquanto o microfone indicar silêncio.
    if (_speechActive) {
      _estimatedPosition = math.max(_estimatedPosition, (index + 1).toDouble());
    }
  }

  /// Retorna o foco atual. Passos grandes do relógio não geram saltos.
  int tick(int nowMillis) {
    final previous = _lastTickMillis;
    _lastTickMillis = nowMillis;
    if (previous == null || !_speechActive || wordCount == 0) {
      return focusIndex;
    }
    final millis = (nowMillis - previous).clamp(0, 250).toInt();
    final anchor = math.max(0, _confirmedIndex + 1);
    final upperBound = math.min(
      wordCount - 1.0,
      anchor + _maxUnconfirmedWords.toDouble(),
    );
    _estimatedPosition = math.min(
      upperBound,
      _estimatedPosition + millis * _wordsPerSecond / 1000,
    );
    return focusIndex;
  }

  /// Reinicia a previsão após busca manual ou novo roteiro. `index` é a
  /// última palavra já lida; o próximo foco é index + 1.
  void seek(int index) {
    _confirmedIndex = index.clamp(-1, wordCount - 1).toInt();
    _estimatedPosition = (_confirmedIndex + 1).toDouble();
    _speechActive = false;
    _lastTickMillis = null;
    _lastConfirmationMillis = null;
    _lastConfirmationIndex = -1;
    _wordsPerSecond = 2.6;
  }
}
