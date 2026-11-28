import 'dart:collection';
import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'wav_pcm_writer.dart';

/// Local, opt-in diagnostic buffer. Audio is saved only after explicit consent.
final voiceTrace = VoiceTrace();

class VoiceTrace {
  VoiceTrace({this.capacity = 30000}) : assert(capacity > 0);
  final int capacity;
  final _events = ListQueue<Map<String, Object?>>();
  bool enabled = false;
  bool recordAudio = false;
  int _originUs = 0;
  int _dropped = 0;
  String? _startedAt;
  int _audioSamples = 0;
  int _captureSession = 0;
  bool _audioTruncated = false;
  bool _audioWriteFailed = false;
  bool _audioLimitNotified = false;
  WavPcmWriter? _audioWriter;
  String? _audioPath;

  static const int _sampleRate = 16000;
  static const int _maxAudioSamples = _sampleRate * 240;

  bool get hasData => _events.isNotEmpty;
  int get count => _events.length;
  String? get audioPath => _audioPath;

  Future<void> start({required bool recordAudio}) async {
    if (enabled || _audioWriter != null) {
      throw StateError('Diagnóstico já está ativo.');
    }
    if (_audioPath != null) {
      try { await File(_audioPath!).delete(); } catch (_) {}
    }
    _audioPath = null;
    _audioSamples = 0;
    _captureSession = 0;
    _audioTruncated = false;
    _audioWriteFailed = false;
    _audioLimitNotified = false;
    this.recordAudio = recordAudio;

    _events.clear();
    _dropped = 0;
    _originUs = Timeline.now;
    _startedAt = DateTime.now().toUtc().toIso8601String();

    if (recordAudio) {
      final dir = await getTemporaryDirectory();
      final folder = await Directory('${dir.path}/flowtext_build35').create(recursive: true);
      _audioPath = '${folder.path}/flowtext_build35_audio.wav';
      try {
        if (await File(_audioPath!).exists()) await File(_audioPath!).delete();
        _audioWriter = await WavPcmWriter.open(_audioPath!, sampleRate: _sampleRate);
      } catch (_) {
        _audioPath = null;
        this.recordAudio = false;
        rethrow;
      }
    }

    enabled = true;
    add('trace_start', {
      'build': '0.10.0+35',
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'logical_processors': Platform.numberOfProcessors,
      'clock': 'Dart Timeline.now; microseconds',
      'record_audio': recordAudio,
      'audio_format': recordAudio ? 'WAV PCM16 mono 16000 Hz; exact PCM chunks passed to Nemotron' : null,
      'token_boundary_format': 'whitespace-prefixed sherpa tokens and SentencePiece ▁ markers',
      'audio_max_seconds': recordAudio ? 240 : null,
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

  void beginMicCapture({required String engine, required int sampleRate}) {
    if (!enabled) return;
    _captureSession++;
    add('mic_capture_start', {
      'capture_session': _captureSession,
      'engine': engine,
      'sample_rate': sampleRate,
      'audio_sample_start': _audioSamples,
    });
  }

  void endMicCapture({String reason = 'stop'}) {
    if (!enabled || _captureSession == 0) return;
    add('mic_capture_stop', {
      'capture_session': _captureSession,
      'reason': reason,
      'audio_sample_end': _audioSamples,
    });
    _captureSession = 0;
  }

  /// Saves the exact PCM16 bytes forwarded to the active ASR worker.
  /// Pauses are omitted from the WAV; JSON timestamps retain those gaps.
  void addPcm(Uint8List bytes) {
    if (!enabled || !recordAudio || _audioWriter == null || bytes.isEmpty) return;
    final evenBytes = bytes.lengthInBytes - (bytes.lengthInBytes % 2);
    if (evenBytes == 0) return;
    final availableSamples = _maxAudioSamples - _audioSamples;
    if (availableSamples <= 0) {
      _markAudioLimit();
      return;
    }
    final inputSamples = evenBytes ~/ 2;
    final keptSamples = inputSamples < availableSamples ? inputSamples : availableSamples;
    final keptBytes = keptSamples * 2;
    final pcm = keptBytes == bytes.lengthInBytes
        ? bytes
        : Uint8List.sublistView(bytes, 0, keptBytes);
    final sampleStart = _audioSamples;
    try {
      _audioWriter!.addPcm(pcm);
      _audioSamples += keptSamples;
      add('audio_pcm_chunk', {
        'capture_session': _captureSession,
        'sample_start': sampleStart,
        'sample_count': keptSamples,
        'audio_start_ms': sampleStart * 1000 / _sampleRate,
        'audio_end_ms': _audioSamples * 1000 / _sampleRate,
      });
      if (keptSamples < inputSamples) {
        _audioTruncated = true;
        _markAudioLimit();
      }
    } catch (e) {
      _audioWriteFailed = true;
      recordAudio = false;
      add('audio_write_error', {'message': '$e'});
    }
  }

  void _markAudioLimit() {
    _audioTruncated = true;
    if (_audioLimitNotified) return;
    _audioLimitNotified = true;
    add('audio_limit_reached', {'max_seconds': 240, 'sample_count': _audioSamples});
  }

  Future<void> stop() async {
    if (!enabled && _audioWriter == null) return;
    if (_captureSession != 0) endMicCapture(reason: 'diagnostic_finished');
    final writer = _audioWriter;
    _audioWriter = null;
    if (writer != null) {
      try {
        await writer.close();
        if (_audioWriteFailed) {
          add('audio_finalize_error', {'message': 'Falha na escrita PCM; WAV descartado.'});
          try { await File(_audioPath!).delete(); } catch (_) {}
          _audioPath = null;
        } else {
          add('audio_finalized', {
            'sample_count': _audioSamples,
            'duration_ms': _audioSamples * 1000 / _sampleRate,
            'truncated': _audioTruncated,
            'file': 'flowtext_build35_audio.wav',
          });
        }
      } catch (e) {
        add('audio_finalize_error', {'message': '$e'});
        try { if (_audioPath != null) await File(_audioPath!).delete(); } catch (_) {}
        _audioPath = null;
      }
    }
    add('trace_stop', {
      'audio_sample_count': _audioSamples,
      'audio_truncated': _audioTruncated,
      'audio_available': _audioPath != null,
    });
    enabled = false;
    recordAudio = false;
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'schema': 1,
    'build': '0.10.0+35',
    'started_utc': _startedAt,
    'timeline_origin_us': _originUs,
    'dropped_events': _dropped,
    'audio': _audioPath == null ? null : {
      'file': 'flowtext_build35_audio.wav',
      'format': 'PCM16 mono 16000 Hz',
      'sample_count': _audioSamples,
      'duration_ms': _audioSamples * 1000 / _sampleRate,
      'truncated': _audioTruncated,
      'mapping': 'audio_pcm_chunk.sample_start/sample_count and event t_us map WAV samples to trace clock; pauses are omitted and capture sessions are identified by capture_session',
    },
    'contains': 'script, ASR hypotheses, timing events and optional local PCM WAV; shared only after user export',
    'events': _events.toList(),
  });
}
