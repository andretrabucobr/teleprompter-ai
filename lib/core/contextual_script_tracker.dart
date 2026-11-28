import 'asr_word_timing.dart';
import 'script_matcher.dart';
import 'spoken_forms_pt.dart';

class TimedScriptWordMatch {
  const TimedScriptWordMatch({
    required this.index,
    required this.startSeconds,
    required this.endSeconds,
    required this.recognizedText,
    required this.heardStartIndex,
    required this.heardEndIndex,
  });

  final int index;
  final double startSeconds;
  final double endSeconds;
  final String recognizedText;
  final int heardStartIndex;
  final int heardEndIndex;
}

class TimedTrackingUpdate {
  const TimedTrackingUpdate(this.state, this.matches, {this.revised = false});

  final TrackingUpdate state;
  final List<TimedScriptWordMatch> matches;
  final bool revised;
}

class TrackingUpdate {
  const TrackingUpdate(this.confirmed, this.display, this.highlight);
  final int confirmed;
  final int display;
  final int highlight;
}

/// Replays each cumulative partial from the last committed utterance.
/// Revisions can change the visual cursor without consuming duplicate words.
class ContextualScriptTracker {
  ContextualScriptTracker(String script, {int anchor = -1, int highlight = -1})
      : words = ScriptMatcher.tokenize(script),
        _confirmed = anchor, _display = anchor,
        _confirmedHighlight = highlight, _highlight = highlight {
    _forms = words.map(spokenForms).toList();
  }

  final List<ScriptWord> words;
  late final List<List<List<String>>> _forms;
  int _confirmed, _display, _confirmedHighlight, _highlight;
  String? _lastPartial, _lastFinal;
  String? _lastTimedPartial, _lastTimedFinal;

  TrackingUpdate get state => TrackingUpdate(_confirmed, _display, _highlight);

  /// Reinicia o alinhamento após uma busca manual, sem reaproveitar
  /// hipóteses temporizadas da posição anterior.
  void seek(int index, {int? highlight}) {
    _confirmed = index.clamp(-1, words.length - 1).toInt();
    _display = _confirmed;
    _confirmedHighlight = highlight ?? -1;
    _highlight = _confirmedHighlight;
    _lastPartial = null;
    _lastFinal = null;
    _lastTimedPartial = null;
    _lastTimedFinal = null;
  }

  /// Alinha palavras reconstruídas dos tokens, preservando a ordem e os tempos.
  /// A hipótese continua cumulativa; somente a extensão nova é devolvida à UI.
  TimedTrackingUpdate acceptTimedWords(
    List<AsrWordTiming> timedWords, {
    required bool isFinal,
    bool adjacentOnly = false,
    bool allowRewind = true,
  }) {
    final valid = <AsrWordTiming>[];
    final heard = <String>[];
    for (final word in timedWords) {
      final normalized = ScriptMatcher.normalize(word.text);
      if (normalized.isEmpty) continue;
      valid.add(word);
      heard.add(normalized);
    }
    if (heard.isEmpty || words.isEmpty) {
      return TimedTrackingUpdate(state, const []);
    }

    final key = heard.join(' ');
    final previous = _lastTimedPartial;
    if (!isFinal && key == previous) {
      return TimedTrackingUpdate(state, const []);
    }
    if (isFinal && previous == null && key == _lastTimedFinal) {
      return TimedTrackingUpdate(state, const []);
    }

    final previousWords = previous?.split(' ') ?? const <String>[];
    var commonPrefix = 0;
    while (commonPrefix < previousWords.length &&
        commonPrefix < heard.length &&
        previousWords[commonPrefix] == heard[commonPrefix]) {
      commonPrefix++;
    }
    final revised = previousWords.isNotEmpty &&
        commonPrefix < previousWords.length;

    var path = _walkTimed(valid, heard, _confirmed, adjacentOnly);
    var recoveredPrefix = false;
    if (!adjacentOnly && (path.isEmpty || path.last.index == _confirmed)) {
      final prefixAnchor = _localPrefixAnchor(
        heard,
        allowRewind: allowRewind,
      );
      if (prefixAnchor != null) {
        path = _walkTimed(valid, heard, prefixAnchor, false);
        recoveredPrefix = true;
      } else if (path.isEmpty) {
        final recovered = _recover(heard, allowRewind, isFinal);
        if (recovered != null) {
          final count = heard.length >= 4 ? 4 : 3;
          final heardStart = heard.length - count;
          final scriptStart = recovered - count + 1;
          for (var i = 0; i < count; i++) {
            final source = valid[heardStart + i];
            path.add(TimedScriptWordMatch(
              index: scriptStart + i,
              startSeconds: source.startSeconds,
              endSeconds: source.endSeconds,
              recognizedText: source.text,
              heardStartIndex: heardStart + i,
              heardEndIndex: heardStart + i,
            ));
          }
        }
      }
    }

    final target = path.isEmpty ? _confirmed : path.last.index;
    _display = target;
    _highlight = target == _confirmed && !recoveredPrefix
        ? _confirmedHighlight
        : target;

    if (isFinal) {
      _confirmed = target;
      _confirmedHighlight = _highlight;
      _lastTimedFinal = key;
      _lastTimedPartial = null;
    } else {
      _lastTimedPartial = key;
    }

    final newMatches = path
        .where((match) => match.heardEndIndex >= commonPrefix)
        .toList(growable: false);
    return TimedTrackingUpdate(
      state,
      List.unmodifiable(newMatches),
      revised: revised,
    );
  }

  List<TimedScriptWordMatch> _walkTimed(
    List<AsrWordTiming> timed,
    List<String> heard,
    int anchor,
    bool adjacentOnly,
  ) {
    final matches = <TimedScriptWordMatch>[];
    var cursor = anchor;
    var i = 0;
    var exactAnchor = false;

    TimedScriptWordMatch makeMatch(int scriptIndex, int from, int length) {
      final first = timed[from];
      final last = timed[from + length - 1];
      return TimedScriptWordMatch(
        index: scriptIndex,
        startSeconds: first.startSeconds,
        endSeconds: last.endSeconds,
        recognizedText: timed
            .sublist(from, from + length)
            .map((word) => word.text)
            .join(' '),
        heardStartIndex: from,
        heardEndIndex: from + length - 1,
      );
    }

    while (i < heard.length && cursor + 1 < words.length) {
      final next = cursor + 1;
      final length = _match(next, heard, i);
      if (length > 0) {
        matches.add(makeMatch(next, i, length));
        cursor = next;
        i += length;
        exactAnchor = true;
        continue;
      }
      if (adjacentOnly) break;

      if (_near(heard[i], words[next].normalized) &&
          (exactAnchor || _match(next + 1, heard, i + 1) > 0)) {
        matches.add(makeMatch(next, i, 1));
        cursor = next;
        i++;
        exactAnchor = false;
        continue;
      }
      if (_match(next, heard, i + 1) > 0) {
        i++;
        continue;
      }
      if (cursor == anchor) break;

      final afterError = _match(next + 1, heard, i + 1);
      if (afterError > 0 &&
          _match(next + 2, heard, i + 1 + afterError) > 0) {
        matches.add(makeMatch(next + 1, i + 1, afterError));
        cursor = next + 1;
        i += 1 + afterError;
        exactAnchor = true;
        continue;
      }

      var found = false;
      for (var skip = 1; skip <= 2 && next + skip < words.length; skip++) {
        final skippedLength = _match(next + skip, heard, i);
        if (skippedLength > 0 &&
            _match(next + skip + 1, heard, i + skippedLength) > 0) {
          matches.add(makeMatch(next + skip, i, skippedLength));
          cursor = next + skip;
          i += skippedLength;
          exactAnchor = true;
          found = true;
          break;
        }
      }
      if (!found) break;
    }
    return matches;
  }

  TrackingUpdate accept(String transcript, {required bool isFinal,
      bool adjacentOnly = false, bool allowRewind = true}) {
    final heard = ScriptMatcher.tokenize(transcript).map((w) => w.normalized).toList();
    if (heard.isEmpty || words.isEmpty) return state;
    final key = heard.join(' ');
    if (!isFinal && key == _lastPartial) return state;
    if (isFinal && _lastPartial == null && key == _lastFinal) return state;
    var target = _walk(heard, _confirmed, adjacentOnly);
    var recoveredPrefix = false;
    if (!adjacentOnly && target == _confirmed) {
      // A speech hypothesis can begin after a skipped title or sentence.
      // Anchor its PREFIX, not its moving tail: longer partials must keep
      // following the same passage even after the first 8 words.
      final prefixAnchor = _localPrefixAnchor(heard, allowRewind: allowRewind);
      if (prefixAnchor != null) {
        target = _walk(heard, prefixAnchor, false);
        recoveredPrefix = true;
      } else {
        final recovered = _recover(heard, allowRewind, isFinal);
        if (recovered != null) target = recovered;
      }
    }
    _display = target;
    _highlight = target == _confirmed && !recoveredPrefix ? _confirmedHighlight : target;
    if (isFinal) {
      _confirmed = target;
      _confirmedHighlight = _highlight;
      _lastFinal = key;
      _lastPartial = null;
    } else {
      _lastPartial = key;
    }
    return state;
  }

  int _match(int at, List<String> heard, int i) {
    if (at < 0 || at >= words.length || i >= heard.length) return 0;
    for (final form in _forms[at]) {
      if (i + form.length > heard.length) continue;
      var equal = true;
      for (var j = 0; j < form.length; j++) {
        if (form[j] != heard[i+j]) { equal = false; break; }
      }
      if (equal) return form.length;
    }
    return 0;
  }

  int _walk(List<String> heard, int anchor, bool adjacentOnly) {
    var cursor = anchor;
    var i = 0;
    var exactAnchor = false;
    while (i < heard.length && cursor + 1 < words.length) {
      final next = cursor + 1;
      final length = _match(next, heard, i);
      if (length > 0) {
        cursor = next;
        i += length;
        exactAnchor = true;
        continue;
      }
      if (adjacentOnly) break;
      if (_near(heard[i], words[next].normalized) &&
          (exactAnchor || _match(next + 1, heard, i + 1) > 0)) {
        cursor = next;
        i++;
        exactAnchor = false;
        continue;
      }
      if (_match(next, heard, i + 1) > 0) {
        i++;
        continue;
      }
      // Before an acoustic anchor is established, all skipped starts must
      // be compared for ambiguity by _localPrefixAnchor. A greedy skip here
      // would select the first repeated phrase and bypass that protection.
      if (cursor == anchor) break;
      // A single mistranscribed word must not block the whole remainder.
      // Advance only when two following script words actually match.
      final afterError = _match(next + 1, heard, i + 1);
      if (afterError > 0 && _match(next + 2, heard, i + 1 + afterError) > 0) {
        cursor = next + 1;
        i += 1 + afterError;
        exactAnchor = true;
        continue;
      }
      var found = false;
      for (var skip = 1; skip <= 2 && next + skip < words.length; skip++) {
        final length = _match(next + skip, heard, i);
        if (length > 0 && _match(next + skip + 1, heard, i + length) > 0) {
          cursor = next + skip;
          i += length;
          exactAnchor = true;
          found = true;
          break;
        }
      }
      if (!found) break;
    }
    return cursor;
  }

  /// Two exact consecutive words in a unique nearby passage are enough.
  /// If a longer prefix disambiguates repetitions, prefer that evidence.
  /// Never skip based on a single isolated word.
  int? _localPrefixAnchor(List<String> heard, {required bool allowRewind}) {
    if (heard.length < 2) return null;
    var bestCount = 1;
    int? best;
    var tied = false;
    final first = allowRewind
        ? (_confirmed - 48).clamp(0, words.length).toInt()
        : _confirmed + 2;
    final last = (_confirmed + 8).clamp(0, words.length - 1).toInt();
    for (var start = first; start <= last; start++) {
      var offset = 0;
      var count = 0;
      var at = start;
      while (offset < heard.length && at < words.length) {
        final length = _match(at, heard, offset);
        if (length == 0) break;
        offset += length;
        at++;
        count++;
      }
      // Reopening a passage needs stronger evidence than a forward skip.
      // Three consecutive words at the very beginning can recover a
      // deliberately restarted script; elsewhere require four.
      final minimum = start <= _confirmed ? (start == 0 ? 3 : 4) : 2;
      if (start == _confirmed + 1 || count < minimum) continue;
      if (count > bestCount) {
        bestCount = count;
        best = start - 1;
        tied = false;
      } else if (count == bestCount && count >= 2) {
        tied = true;
      }
    }
    return tied ? null : best;
  }

  int? _recover(List<String> heard, bool allowRewind, bool isFinal) {
    if (heard.length < 3) return null;
    final count = heard.length >= 4 ? 4 : 3;
    final tail = heard.sublist(heard.length - count);
    final lo = (_confirmed - (allowRewind && count == 4 ? 48 : 0)).clamp(0, words.length).toInt();
    final hi = (_confirmed + (isFinal ? 40 : 8)).clamp(0, words.length - 1).toInt();
    final hits = <int>[];
    for (var end = lo; end <= hi; end++) {
      if (end - count + 1 < 0) continue;
      if (end < _confirmed && (!allowRewind || count < 4)) continue;
      var match = true;
      for (var j = 0; j < count; j++) {
        if (words[end - count + 1 + j].normalized != tail[j]) { match = false; break; }
      }
      if (match) hits.add(end);
    }
    return hits.length == 1 ? hits.single : null;
  }

  static bool _near(String a, String b) {
    if (a == b) return true;
    if (a.length < 3 || b.length < 3) return false;
    if (a.contains('lh') != b.contains('lh')) {
      final reference = a.contains('lh') ? a : b;
      final other = a.contains('lh') ? b : a;
      return ['i', 'li', ''].any((x) => reference.replaceAll('lh', x) == other);
    }
    if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, errors = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) { i++; j++; continue; }
      if (++errors > 1) return false;
      if (a.length >= b.length) i++;
      if (b.length >= a.length) j++;
    }
    return errors + a.length - i + b.length - j <= 1;
  }
}
