import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/script_matcher.dart';
import 'package:teleprompter_ai/widgets/flow_reader_text.dart';

void main() {
  testWidgets('cursor repinta sem mudar a geometria do roteiro', (tester) async {
    const text = 'Bom dia, hoje vamos apresentar nosso projeto.';
    final words = ScriptMatcher.tokenize(text);
    final cursor = ValueNotifier<int>(-1);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: FlowReaderText(text: text, words: words,
        style: const TextStyle(fontSize: 36, height: 1.5), highlight: cursor),
    ))));
    final render = tester.renderObject<FlowReaderRender>(find.byType(FlowReaderText));
    final size = render.size;
    final first = render.getBoxesForSelection(TextSelection(
      baseOffset: words.first.start, extentOffset: words.first.end)).first.toRect();
    cursor.value = 0;
    expect(render.debugNeedsLayout, isFalse);
    await tester.pump();
    cursor.value = 1;
    expect(render.debugNeedsLayout, isFalse);
    await tester.pump();
    expect(render.size, size);
    expect(render.getBoxesForSelection(TextSelection(
      baseOffset: words.first.start, extentOffset: words.first.end)).first.toRect(), first);
    await tester.pumpWidget(const SizedBox());
    cursor.dispose();
  });
}
