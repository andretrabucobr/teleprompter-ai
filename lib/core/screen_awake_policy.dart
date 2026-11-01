/// Política de tela ativa: mantém o display ligado apenas durante uma sessão
/// de teleprompter, com o aplicativo em primeiro plano.
/// Não impede o bloqueio manual nem mantém o app executando em background.
class ScreenAwakePolicy {
  const ScreenAwakePolicy._();

  static bool shouldKeepAwake({
    required bool foreground,
    required bool fullScreen,
    required bool playing,
    required bool recording,
    required bool preparing,
  }) =>
      foreground && (fullScreen || playing || recording || preparing);
}
