/// Decides whether an ASR result may move the reader in voice mode.
///
/// Energy-based VAD is best-effort, but its pause event is authoritative
/// for *screen movement*: a delayed partial/final result must never start
/// scrolling again while the speaker is silent.
enum VoiceScrollDecision { ignore, advance, highlightOnly }

class VoiceScrollGate {
  VoiceScrollGate({
    this.trailingHighlightWindow = const Duration(milliseconds: 900),
  });

  final Duration trailingHighlightWindow;
  bool _speaking = false;
  DateTime? _lastStoppedAt;
  bool _hasSpoken = false;
  bool _usedTrailingHighlight = false;

  bool get isSpeaking => _speaking;

  /// Receives transitions from the same PCM stream used for recording.
  void onSpeechActivity(bool speaking, {DateTime? at}) {
    if (speaking) {
      if (!_speaking) {
        _lastStoppedAt = null;
        _usedTrailingHighlight = false;
      }
      _speaking = true;
      _hasSpoken = true;
    } else {
      if (_speaking) {
        _lastStoppedAt = at ?? DateTime.now();
      }
      _speaking = false;
    }
  }

  /// Native STT does not expose PCM/VAD in this app, so it is handled as a
  /// transcript-only fallback. The streaming/Whisper engines have VAD.
  VoiceScrollDecision decide({
    required bool hasActivityDetector,
    DateTime? at,
  }) {
    if (!hasActivityDetector) return VoiceScrollDecision.advance;
    if (_speaking) return VoiceScrollDecision.advance;
    if (!_hasSpoken || _usedTrailingHighlight || _lastStoppedAt == null) {
      return VoiceScrollDecision.ignore;
    }
    final delay = (at ?? DateTime.now()).difference(_lastStoppedAt!);
    if (delay.isNegative || delay > trailingHighlightWindow) {
      return VoiceScrollDecision.ignore;
    }
    // One late result may correct the highlighted last word, WITHOUT
    // moving the viewport. After it, the reading position is frozen.
    return VoiceScrollDecision.highlightOnly;
  }

  /// Call only if a different word was actually confirmed by the aligner.
  void onConfirmed(VoiceScrollDecision decision) {
    if (decision == VoiceScrollDecision.highlightOnly) {
      _usedTrailingHighlight = true;
    }
  }

  void reset() {
    _speaking = false;
    _lastStoppedAt = null;
    _hasSpoken = false;
    _usedTrailingHighlight = false;
  }
}
