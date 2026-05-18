import 'package:flutter/material.dart';
import 'screens/ui_screens/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'config/theme_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeepLinkService().init();
  await ThemeNotifier().load();
  runApp(const ScannerApp());
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
          home: const SplashScreen(),
        );
      },
    );
  }
}
