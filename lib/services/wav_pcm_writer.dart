import 'dart:io';
import 'dart:typed_data';

/// WAV PCM16 mono; recebe exatamente os bytes produzidos pelo único microfone.
/// Evita carregar a gravação inteira em memória, inclusive em sessões longas.
class WavPcmWriter {
  WavPcmWriter._(this.path, this.sampleRate, this._handle);

  static const int headerSize = 44;
  final String path;
  final int sampleRate;
  final RandomAccessFile _handle;
  Future<void> _writes = Future<void>.value();
  Future<String>? _closing;
  int _dataBytes = 0;
  bool _closed = false;

  int get sampleCount => _dataBytes ~/ 2;

  static Future<WavPcmWriter> open(String path, {int sampleRate = 16000}) async {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    await File(path).parent.create(recursive: true);
    final handle = await File(path).open(mode: FileMode.write);
    await handle.writeFrom(Uint8List(headerSize));
    return WavPcmWriter._(path, sampleRate, handle);
  }

  void addPcm(Uint8List bytes) {
    if (_closed) throw StateError('WAV já fechado.');
    if (bytes.lengthInBytes.isOdd) {
      throw ArgumentError('PCM16 precisa conter um número par de bytes.');
    }
    // Um único RandomAccessFile mantém a posição e evita reabrir/truncar
    // o arquivo durante a escrita do cabeçalho RIFF no final.
    final copy = Uint8List.fromList(bytes);
    _writes = _writes.then((_) async { await _handle.writeFrom(copy); });
    _dataBytes += copy.lengthInBytes;
  }

  Future<String> close() => _closing ??= _closeInternal();

  Future<String> _closeInternal() async {
    _closed = true;
    try {
      await _writes;
      await _handle.setPosition(0);
      await _handle.writeFrom(header(_dataBytes, sampleRate));
      await _handle.flush();
      return path;
    } finally {
      await _handle.close();
    }
  }

  /// Recorta amostras sem modificar o original; útil para alinhar o áudio
  /// iniciado antes do comando de gravação da câmera.
  static Future<String> clip({
    required String source,
    required String destination,
    required int firstSample,
    required int lastSample,
    int sampleRate = 16000,
  }) async {
    if (firstSample < 0 || lastSample <= firstSample) {
      throw RangeError('Intervalo inválido de áudio: $firstSample..$lastSample');
    }
    final input = await File(source).open();
    final output = await WavPcmWriter.open(destination, sampleRate: sampleRate);
    try {
      final bytesAvailable = (await input.length()) - headerSize;
      final start = firstSample * 2;
      final end = lastSample * 2;
      if (start >= bytesAvailable || end > bytesAvailable) {
        throw RangeError('O recorte ultrapassa a gravação PCM.');
      }
      await input.setPosition(headerSize + start);
      var remaining = end - start;
      while (remaining > 0) {
        final chunk = await input.read(remaining < 65536 ? remaining : 65536);
        if (chunk.isEmpty) throw const FileSystemException('WAV incompleto');
        output.addPcm(Uint8List.fromList(chunk));
        remaining -= chunk.length;
      }
      return await output.close();
    } catch (_) {
      await output.close();
      if (await File(destination).exists()) {
        await File(destination).delete();
      }
      rethrow;
    } finally {
      await input.close();
    }
  }

  static Uint8List header(int lengthBytes, int sampleRate) {
    if (lengthBytes < 0 || lengthBytes.isOdd) {
      throw ArgumentError.value(lengthBytes, 'lengthBytes');
    }
    final bytes = Uint8List(headerSize);
    final values = ByteData.sublistView(bytes);
    void ascii(int pos, String name) {
      for (var i = 0; i < name.length; i++) {
        bytes[pos + i] = name.codeUnitAt(i);
      }
    }
    ascii(0, 'RIFF');
    values.setUint32(4, lengthBytes + 36, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    values.setUint32(16, 16, Endian.little); // PCM fmt size
    values.setUint16(20, 1, Endian.little); // PCM sem compressão
    values.setUint16(22, 1, Endian.little); // mono
    values.setUint32(24, sampleRate, Endian.little);
    values.setUint32(28, sampleRate * 2, Endian.little);
    values.setUint16(32, 2, Endian.little);
    values.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    values.setUint32(40, lengthBytes, Endian.little);
    return bytes;
  }
}
