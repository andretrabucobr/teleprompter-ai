import 'dart:async';
import 'asr_worker.dart';

/// Owns only an idle recognizer, never the microphone. Serial operations
/// prevent a concurrent preload and playback from creating two models.
class WarmVoiceCache<T extends AsrWorker> {
  WarmVoiceCache(this._create);
  final Future<T?> Function() _create;
  T? _idle;
  bool get isReady => _idle != null;
  Future<void> _tail = Future<void>.value();

  Future<R> _serial<R>(Future<R> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> prepare() => _serial(() async {
    if (_idle != null) return true;
    _idle = await _create();
    return _idle != null;
  });

  /// Does not create a model if none is cached. Caller may cold-start.
  Future<T?> take() => _serial(() async {
    final worker = _idle;
    _idle = null;
    return worker;
  });

  /// Takes ownership of an already suspended worker.
  Future<void> store(T worker) => _serial(() async {
    final old = _idle;
    _idle = worker;
    if (old != null && !identical(old, worker)) await old.stop();
  });

  Future<void> release() => _serial(() async {
    final worker = _idle;
    _idle = null;
    await worker?.stop();
  });
}
