import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/services/asr_worker.dart';
import 'package:teleprompter_ai/services/warm_voice_cache.dart';

class FakeVoice implements AsrWorker {
  int stops = 0;
  @override
  Future<void> start() async {}
  @override
  void addPcm(Uint8List pcm) {}
  @override
  void suspend() {}
  @override
  void resume() {}
  @override
  Future<void> stop() async { stops++; }
}

void main() {
  test('preload e play simultâneos compartilham o mesmo worker', () async {
    final ready = Completer<FakeVoice>();
    var creates = 0;
    final cache = WarmVoiceCache<FakeVoice>(() { creates++; return ready.future; });
    final preparing = cache.prepare();
    final secondPrepare = cache.prepare();
    final taking = cache.take();
    final worker = FakeVoice();
    ready.complete(worker);
    expect(await preparing, true);
    expect(await secondPrepare, true);
    expect(await taking, same(worker));
    expect(creates, 1);
    expect(await cache.take(), isNull);
    await cache.store(worker);
    expect(await cache.take(), same(worker));
    expect(worker.stops, 0);
    await worker.stop();
  });
  test('release durante preload encerra worker ocioso uma vez', () async {
    final ready = Completer<FakeVoice>();
    final cache = WarmVoiceCache<FakeVoice>(() => ready.future);
    final preparing = cache.prepare();
    final releasing = cache.release();
    final worker = FakeVoice();
    ready.complete(worker);
    await preparing;
    await releasing;
    await cache.release();
    expect(worker.stops, 1);
    expect(await cache.take(), isNull);
  });
  test('cache pode ser reutilizado depois de falha de preparação', () async {
    final worker = FakeVoice();
    var attempts = 0;
    final cache = WarmVoiceCache<FakeVoice>(() async {
      if (++attempts == 1) throw StateError('falha');
      return worker;
    });
    await expectLater(cache.prepare(), throwsStateError);
    expect(await cache.prepare(), true);
    expect(await cache.take(), same(worker));
    await worker.stop();
  });
}
