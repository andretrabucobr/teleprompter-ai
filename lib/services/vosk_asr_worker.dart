import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../core/pcm_frame_accumulator.dart';
import '../core/speech_activity_gate.dart';
import 'asr_worker.dart';

/// Consome o PCM compartilhado; não abre outro microfone.
class VoskAsrWorker implements AsrWorker {
  VoskAsrWorker({required this.onText, required this.onStatus, this.onSpeechActivity});
  final void Function(String, bool) onText;
  final void Function(String) onStatus;
  final void Function(bool)? onSpeechActivity;
  static const _channel = MethodChannel('flowtext/vosk');
  final _frames = PcmFrameAccumulator(frameBytes: 2560);
  final _gate = SpeechActivityGate(minimumSpeechFrames: 2);
  final _queue = Queue<Uint8List>();
  bool _running = false, _following = false, _busy = false, _speaking = false;
  bool _resetNeeded = false;
  int _epoch = 0;
  String _last = '';
  Future<void>? _draining;
  bool get hasRecentSpeechEvidence => _running && _following && _gate.hasRecentSpeechEvidence;

  @override
  Future<void> start() async {
    onStatus('Preparando Vosk pt-BR local...');
    await _channel.invokeMethod<void>('start');
    _running = true;
    _following = true;
    onStatus('Vosk pt-BR pronto.');
  }

  @override
  void addPcm(Uint8List pcm) {
    if (!_running || !_following) return;
    _gate.addPcm(pcm);
    final speaking = _gate.currentlySpeaking;
    if (speaking != _speaking) {
      _speaking = speaking;
      onSpeechActivity?.call(speaking);
    }
    for (final frame in _frames.add(pcm)) {
      if (_queue.length >= 15) {
        // Não processar vários segundos de áudio antigo. O WAV não é afetado.
        _queue.clear();
        _epoch++;
        _resetNeeded = true;
        _last = '';
        onStatus('Vosk sobrecarregado: fila de ASR reiniciada; WAV preservado.');
      }
      _queue.add(frame);
    }
    _pump();
  }

  void _pump() {
    if (_busy || !_running || !_following) return;
    _busy = true;
    _draining = _drain();
  }

  Future<void> _drain() async {
    try {
      while (_running && _following && (_queue.isNotEmpty || _resetNeeded)) {
        if (_resetNeeded) {
          _resetNeeded = false;
          await _channel.invokeMethod<void>('reset');
          continue;
        }
        final frame = _queue.removeFirst();
        final epoch = _epoch;
        final response = await _channel.invokeMapMethod<String, dynamic>('pcm', frame);
        if (!_running || !_following || epoch != _epoch || response == null) continue;
        final text = (response['text'] as String? ?? '').trim();
        final isFinal = response['final'] == true;
        if (text.isNotEmpty && (text != _last || isFinal)) onText(text, isFinal);
        _last = isFinal ? '' : text;
      }
    } catch (e) {
      _following = false;
      _queue.clear();
      onStatus('Falha no Vosk: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void suspend() {
    _following = false;
    _epoch++;
    _queue.clear();
    _frames.reset();
    _gate.reset();
    _last = '';
    _resetNeeded = true;
    if (_speaking) {
      _speaking = false;
      onSpeechActivity?.call(false);
    }
  }

  @override
  void resume() {
    if (!_running) throw StateError('Vosk não inicializado.');
    _following = true;
    _pump();
  }

  @override
  Future<void> stop() async {
    suspend();
    _running = false;
    await _draining;
    await _channel.invokeMethod<void>('stop');
  }
}
