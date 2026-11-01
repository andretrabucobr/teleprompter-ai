import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/pcm_frame_accumulator.dart';

void main() {
  test('agrupa chunks curtos em frames de 100 ms sem perder ordem', () {
    final f = PcmFrameAccumulator(frameBytes: 4);
    expect(f.add(Uint8List.fromList([1, 2, 3])), isEmpty);
    final result = f.add(Uint8List.fromList([4, 5, 6, 7, 8, 9]));
    expect(result.map((e) => e.toList()).toList(), [[1,2,3,4],[5,6,7,8]]);
    expect(f.bufferedBytes, 1);
    expect(f.add(Uint8List.fromList([10,11,12])).single.toList(), [9,10,11,12]);
  });

  test('preserva byte ímpar entre pacotes de entrada', () {
    final f = PcmFrameAccumulator(frameBytes: 4);
    expect(f.add(Uint8List.fromList([255])), isEmpty);
    expect(f.add(Uint8List.fromList([0,1,2])).single.toList(), [255,0,1,2]);
  });

  test('reset descarta áudio antigo ao pausar/retomar', () {
    final f = PcmFrameAccumulator(frameBytes: 4);
    f.add(Uint8List.fromList([1,2,3]));
    f.reset();
    expect(f.add(Uint8List.fromList([4,5,6,7])).single.toList(), [4,5,6,7]);
  });
}
