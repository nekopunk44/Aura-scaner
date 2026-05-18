import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ChangeNotifier {
  static final ThemeNotifier _instance = ThemeNotifier._internal();
  factory ThemeNotifier() => _instance;
  ThemeNotifier._internal();

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    _mode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  Future<void> toggle() async {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

class AppTheme {
  static const _accent = Color(0xFF2CA5E0);

  static final light = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(seedColor: _accent),
    scaffoldBackgroundColor: const Color(0xFFF2F6FC),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      iconTheme: IconThemeData(color: Colors.black87),
      titleTextStyle: TextStyle(
        color: Colors.black87,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardColor: Colors.white,
    dividerColor: Colors.black12,
    iconTheme: const IconThemeData(color: Colors.black87),
  );

  static final dark = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF1A2535),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F1923),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Color(0xFF1A2535),
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardColor: const Color(0xFF1E2D3D),
    dividerColor: Colors.white12,
    iconTheme: const IconThemeData(color: Colors.white),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Colors.white70),
    ),
  );
}
