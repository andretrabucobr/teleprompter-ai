import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teleprompter_ai/screens/startup_splash_page.dart';

void main() {
  testWidgets('a abertura é preta e exibe a logo', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StartupSplashPage()),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
    expect(find.byKey(const ValueKey('startup-logo')), findsOneWidget);
    // Cancela o timer sem precisar inicializar plugins do leitor no teste.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
