import 'package:flutter/material.dart';
import 'screens/ui_screens/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'services/premium_service.dart';
import 'config/sentry_config.dart';
import 'config/theme_config.dart';

void main() async {
  await bootstrapSentry(() async {
    WidgetsFlutterBinding.ensureInitialized();
    DeepLinkService().init();
    await ThemeNotifier().load();
    await PremiumService().load();
    runApp(const ScannerApp());
  });
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeNotifier(),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeNotifier().mode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeOut,
          home: const SplashScreen(),
        );
      },
    );
  }
}
