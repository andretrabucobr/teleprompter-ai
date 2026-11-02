import 'package:flutter/material.dart';

import 'screens/startup_splash_page.dart';
import 'core/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TeleprompterApp());
}

class TeleprompterApp extends StatelessWidget {
  const TeleprompterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Oitosete FlowText',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.brand,
            brightness: Brightness.dark,
          ).copyWith(
            primary: AppColors.brand,
            onPrimary: AppColors.onBrand,
            secondary: AppColors.brand,
            onSecondary: AppColors.onBrand,
          ),
          scaffoldBackgroundColor: AppColors.background,
        ),
        home: const StartupSplashPage(),
      );
}
