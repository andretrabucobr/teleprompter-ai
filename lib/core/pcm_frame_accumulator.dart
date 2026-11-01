import 'dart:typed_data';

/// Divide um fluxo PCM16 mono, little-endian, em blocos de duração fixa.
/// Preserva o byte incompleto entre entregas do microfone.
/// A gravação WAV recebe os dados originais, não os blocos desta classe.
class PcmFrameAccumulator {
  PcmFrameAccumulator({this.frameBytes = 3200})
      : assert(frameBytes > 0 && frameBytes.isEven);

  final int frameBytes; // 3200 bytes = 100 ms a 16 kHz PCM16 mono.
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  List<Uint8List> add(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    _buffer.add(chunk);
    if (_buffer.length < frameBytes) return const [];
    final data = _buffer.takeBytes();
    final fullBytes = data.length - data.length % frameBytes;
    final frames = <Uint8List>[];
    for (var offset = 0; offset < fullBytes; offset += frameBytes) {
      frames.add(Uint8List.sublistView(data, offset, offset + frameBytes));
    }
    if (fullBytes < data.length) _buffer.add(Uint8List.sublistView(data, fullBytes));
    return frames;
  }

  int get bufferedBytes => _buffer.length;
  void reset() => _buffer.clear();
}
