import 'script_matcher.dart';

/// Índices absolutos de palavras; quebras de linha definem parágrafos.
class ReadingNavigation {
  ReadingNavigation(String script, this.words) : starts = [
    if (words.isNotEmpty) 0,
    for (var i = 1; i < words.length; i++)
      if (script.substring(words[i-1].end, words[i].start).contains('\n')) i,
  ];
  final List<ScriptWord> words;
  final List<int> starts;
  int paragraph(int index, int direction) {
    if (starts.isEmpty) return 0;
    var p = starts.lastIndexWhere((start) => start <= index);
    if (p < 0) p = 0;
    if (direction < 0 && index == starts[p]) p--;
    if (direction > 0) p++;
    return starts[p.clamp(0, starts.length - 1).toInt()];
  }
  int atOffset(int offset) {
    if (words.isEmpty) return 0;
    var lo = 0, hi = words.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (words[mid].end <= offset) { lo = mid + 1; } else { hi = mid; }
    }
    return lo;
  }
}
