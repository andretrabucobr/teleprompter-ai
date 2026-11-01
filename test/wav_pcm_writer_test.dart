import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/services/wav_pcm_writer.dart';

void main() {
  test('cabeçalho PCM16 mono 16 kHz declara RIFF, data e sample rate', () {
    final bytes = WavPcmWriter.header(8, 16000);
    final data = ByteData.sublistView(bytes);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(data.getUint32(40, Endian.little), 8);
  });

  test('WAV não perde os bytes PCM ao finalizar nem ao recortar', () async {
    final dir = await Directory.systemTemp.createTemp('teleprompter_pcm_');
    try {
      final source = '${dir.path}/source.wav';
      final cut = '${dir.path}/cut.wav';
      final writer = await WavPcmWriter.open(source);
      writer.addPcm(Uint8List.fromList([1, 0, 2, 0, 3, 0, 4, 0]));
      expect(writer.sampleCount, 4);
      await writer.close();
      final actual = await File(source).readAsBytes();
      expect(actual.length, 52);
      expect(actual.sublist(44), [1, 0, 2, 0, 3, 0, 4, 0]);
      expect(ByteData.sublistView(actual).getUint32(40, Endian.little), 8);

      await WavPcmWriter.clip(
        source: source, destination: cut, firstSample: 1, lastSample: 3,
      );
      final clip = await File(cut).readAsBytes();
      expect(clip.length, 48);
      expect(clip.sublist(44), [2, 0, 3, 0]);
      expect(ByteData.sublistView(clip).getUint32(40, Endian.little), 4);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('recusa intervalo PCM fora do arquivo', () async {
    final dir = await Directory.systemTemp.createTemp('teleprompter_pcm_bad_');
    try {
      final path = '${dir.path}/pcm.wav';
      final writer = await WavPcmWriter.open(path);
      writer.addPcm(Uint8List.fromList([1, 0]));
      await writer.close();
      await expectLater(
        WavPcmWriter.clip(
          source: path, destination: '${dir.path}/invalid.wav',
          firstSample: 0, lastSample: 999,
        ),
        throwsRangeError,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
