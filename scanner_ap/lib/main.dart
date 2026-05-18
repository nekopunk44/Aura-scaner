// Точка входа приложения Aura Scanner.
//
// Приложение для сканирования документов, паспортов, ID-карт,
// распознавания текста (OCR), перевода через камеру и хранения файлов.
//
// Поток навигации:
//   main() → SplashScreen (3 сек) → MainScreen (нижняя навигация)
import 'package:flutter/material.dart';
import 'screens/ui_screens/splash_screen.dart';

void main() async {
  // Инициализация, необходимая для плагинов (например, camera)
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Используем более светлые цвета по умолчанию, чтобы соответствовать новому стилю
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          elevation: 0, // Убираем тень
          backgroundColor: Colors.white,
          iconTheme: IconThemeData(color: Colors.black),
        ),
      ),
      // Запускаем SplashScreen, который затем перейдет на MainScreen
      home: const SplashScreen(),
    );
  }
}