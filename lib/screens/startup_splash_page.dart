import 'dart:async';
import 'package:flutter/material.dart';
import 'teleprompter_page.dart';

/// Abertura do Oitosete FlowText com a logo original sobre preto puro.
/// Depois do primeiro frame do Flutter, mantém a logo brevemente em tela.
class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key});

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage> {
  Timer? _navigation;

  @override
  void initState() {
    super.initState();
    _navigation = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const TeleprompterPage()),
      );
    });
  }

  @override
  void dispose() {
    _navigation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Image.asset('assets/branding/otst_logo.png',
                  key: const ValueKey('startup-logo'),
                  fit: BoxFit.contain,
                  width: 290,
                  semanticLabel: 'Logotipo Oitosete FlowText'),
            ),
          ),
        ),
      );
}
