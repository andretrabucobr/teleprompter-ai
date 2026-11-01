import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/core/screen_awake_policy.dart';

void main() {
  bool awake({
    bool foreground = true,
    bool fullScreen = false,
    bool playing = false,
    bool recording = false,
    bool preparing = false,
  }) => ScreenAwakePolicy.shouldKeepAwake(
    foreground: foreground,
    fullScreen: fullScreen,
    playing: playing,
    recording: recording,
    preparing: preparing,
  );

  test('não impede suspensão durante edição', () {
    expect(awake(), isFalse);
  });

  test('mantém a tela acordada na leitura em tela cheia, inclusive pausada', () {
    expect(awake(fullScreen: true), isTrue);
  });

  test('mantém a tela acordada enquanto reproduz, grava ou prepara', () {
    expect(awake(playing: true), isTrue);
    expect(awake(recording: true), isTrue);
    expect(awake(preparing: true), isTrue);
  });

  test('não impede a suspensão com aplicativo em segundo plano', () {
    expect(awake(foreground: false, fullScreen: true,
      playing: true, recording: true), isFalse);
  });
}
