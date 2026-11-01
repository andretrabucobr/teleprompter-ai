import 'dart:typed_data';

/// Contrato do motor de reconhecimento. A gravação PCM/WAV não depende dele.
abstract class AsrWorker {
  Future<void> start();
  void addPcm(Uint8List pcm);
  void suspend();
  void resume();
  Future<void> stop();
}
