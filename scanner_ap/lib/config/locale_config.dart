import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Хранит выбранный пользователем язык приложения.
///
/// `null` = «Системный»: язык берётся из локали устройства (поведение по
/// умолчанию). Иначе — явный override, который переживает перезапуск.
class LocaleNotifier extends ChangeNotifier {
  static final LocaleNotifier _instance = LocaleNotifier._internal();
  factory LocaleNotifier() => _instance;
  LocaleNotifier._internal();

  static const _key = 'app_locale';

  /// Поддерживаемые языки (должны совпадать с supportedLocales в MaterialApp).
  static const supported = [Locale('en'), Locale('ru')];

  Locale? _locale;
  Locale? get locale => _locale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    _locale = code == null ? null : Locale(code);
  }

  /// [locale] = null сбрасывает на системный язык.
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, locale.languageCode);
    }
  }
}
