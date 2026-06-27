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

  void toggle() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', _mode == ThemeMode.dark ? 'dark' : 'light');
  }
}

class AppTheme {
  static const _accent = Color(0xFF2CA5E0);

  static final light = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: _accent,
      secondary: _accent,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFF2F6FC),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1A1A2E),
      iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
      titleTextStyle: TextStyle(
        color: Color(0xFF1A1A2E),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardColor: Colors.white,
    dividerColor: Colors.black12,
    iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1A1A2E)),
      bodyMedium: TextStyle(color: Color(0xFF1A1A2E)),
      bodySmall: TextStyle(color: Color(0xFF6B7A99)),
    ),
  );

  static final dark = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: _accent,
      secondary: _accent,
      surface: Color(0xFF141E2B),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F1923),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: true,
      backgroundColor: Color(0xFF141E2B),
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardColor: const Color(0xFF1E2A3A),
    dividerColor: Colors.white12,
    iconTheme: const IconThemeData(color: Colors.white),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
      bodySmall: TextStyle(color: Colors.white70),
    ),
  );
}
