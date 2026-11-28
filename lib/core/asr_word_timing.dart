/// Palavra reconstruída dos tokens SentencePiece do reconhecedor streaming.
class AsrWordTiming {
  const AsrWordTiming({
    required this.text,
    required this.startSeconds,
    required this.endSeconds,
    required this.tokenCount,
  });

  final String text;
  final double startSeconds;
  final double endSeconds;
  final int tokenCount;
}

/// Hipótese streaming com tempos relativos ao início do segmento de fala.
class AsrTimedTranscript {
  const AsrTimedTranscript({
    required this.text,
    required this.isFinal,
    required this.words,
    required this.audioEndMs,
    required this.segmentStartMs,
  });

  final String text;
  final bool isFinal;
  final List<AsrWordTiming> words;
  final double audioEndMs;
  final double segmentStartMs;
}

/// Agrupa peças BPE/SentencePiece sem perder o timestamp de cada palavra.
class SentencePieceWordDecoder {
  static List<AsrWordTiming> decode(
    List<String> tokens,
    List<double> timestamps,
  ) {
    if (tokens.isEmpty || tokens.length != timestamps.length) {
      return const [];
    }

    final words = <AsrWordTiming>[];
    final buffer = StringBuffer();
    double? start;
    double? end;
    double? pendingBoundary;
    var tokenCount = 0;
    var lastTime = 0.0;

    void flush() {
      final text = buffer.toString().trim();
      if (text.isNotEmpty && start != null && end != null) {
        words.add(AsrWordTiming(
          text: text,
          startSeconds: start!,
          endSeconds: end!,
          tokenCount: tokenCount,
        ));
      }
      buffer.clear();
      start = null;
      end = null;
      tokenCount = 0;
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.isEmpty || token == '<unk>') continue;

      final rawTime = timestamps[i];
      final candidate = rawTime.isFinite && rawTime >= 0
          ? rawTime
          : lastTime;
      final time = candidate < lastTime ? lastTime : candidate;
      lastTime = time;

      if (token == '▁') {
        flush();
        pendingBoundary = time;
        continue;
      }

      if (token.startsWith('▁')) {
        flush();
        final piece = token.substring(1);
        if (piece.isEmpty) {
          pendingBoundary = time;
          continue;
        }
        buffer.write(piece);
        start = pendingBoundary ?? time;
        end = time;
        tokenCount = 1;
        pendingBoundary = null;
        continue;
      }

      // Marcadores de controle não fazem parte de uma palavra falada.
      if (token.startsWith('<') && token.endsWith('>')) continue;

      if (buffer.isEmpty) {
        buffer.write(token);
        start = pendingBoundary ?? time;
        end = time;
        tokenCount = 1;
        pendingBoundary = null;
      } else {
        buffer.write(token);
        end = time;
        tokenCount++;
      }
    }

    flush();
    return List.unmodifiable(words);
  }
}
