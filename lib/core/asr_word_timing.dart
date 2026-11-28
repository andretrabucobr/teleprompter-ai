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

/// Agrupa os tokens emitidos pelo sherpa-onnx em palavras.
/// O Nemotron/sherpa pode emitir tanto marcadores SentencePiece (▁)
/// quanto tokens com espaço ASCII inicial (" T", " de") e tokens
/// contendo somente espaço (" "). Ambos indicam início de palavra.
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

      // Marcadores de controle não fazem parte de uma palavra falada.
      if (token.startsWith('<') && token.endsWith('>')) continue;

      final hasSentencePieceBoundary = token.startsWith('▁');
      final hasWhitespaceBoundary = token.startsWith(' ') ||
          token.startsWith('\\t') || token.startsWith('\\n') ||
          token.startsWith('\\r');
      final piece = hasSentencePieceBoundary
          ? token.substring(1)
          : hasWhitespaceBoundary
              ? token.trimLeft()
              : token;

      if (hasSentencePieceBoundary || hasWhitespaceBoundary) {
        flush();
      }
      if (piece.isEmpty) continue;

      if (buffer.isEmpty) {
        buffer.write(piece);
        start = time;
        end = time;
        tokenCount = 1;
      } else {
        buffer.write(piece);
        end = time;
        tokenCount++;
      }
    }

    flush();
    return List.unmodifiable(words);
  }
}
