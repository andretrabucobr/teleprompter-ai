import 'dart:collection';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';

/// Local, opt-in diagnostic buffer. No microphone samples or network access.
final voiceTrace = VoiceTrace();

class VoiceTrace {
  VoiceTrace({this.capacity = 30000}) : assert(capacity > 0);
  final int capacity;
  final _events = ListQueue<Map<String, Object?>>();
  bool enabled = false;
  int _originUs = 0;
  int _dropped = 0;
  String? _startedAt;

  bool get hasData => _events.isNotEmpty;
  int get count => _events.length;

  void start() {
    _events.clear();
    _dropped = 0;
    _originUs = Timeline.now;
    _startedAt = DateTime.now().toUtc().toIso8601String();
    enabled = true;
    add('trace_start', {
      'build': '0.10.0+27',
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'logical_processors': Platform.numberOfProcessors,
      'clock': 'Dart Timeline.now; microseconds',
    });
  }

  void add(String event, [Map<String, Object?> fields = const {}]) {
    if (!enabled) return;
    if (_events.length >= capacity) {
      _events.removeFirst();
      _dropped++;
    }
    _events.addLast({
      't_us': Timeline.now - _originUs,
      'event': event,
      ...fields,
    });
  }

  void stop() {
    if (!enabled) return;
    add('trace_stop');
    enabled = false;
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'build': '0.10.0+27',
    'started_utc': _startedAt,
    'timeline_origin_us': _originUs,
    'dropped_events': _dropped,
    'contains': 'script and ASR hypotheses; no raw audio or video',
    'events': _events.toList(),
  });
}
