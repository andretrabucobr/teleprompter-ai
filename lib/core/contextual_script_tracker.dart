import 'script_matcher.dart';
import 'spoken_forms_pt.dart';

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

  TrackingUpdate get state => TrackingUpdate(_confirmed, _display, _highlight);

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
