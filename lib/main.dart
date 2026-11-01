import 'package:flutter/material.dart';

import 'screens/teleprompter_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeleprompterApp());
}

class TeleprompterApp extends StatelessWidget {
  const TeleprompterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Teleprompter AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10C4A4),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF111519),
        ),
        home: const TeleprompterPage(),
      );
}
