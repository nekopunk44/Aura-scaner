import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Обёртка над local_auth: проверка доступности, аутентификация и
/// персистентный флаг «биометрический замок включён».
///
/// Флаг хранится в secure storage рядом с токенами — настройка
/// безопасности не должна валяться в обычных prefs.
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();
  static const _enabledKey = 'biometric_enabled';

  bool? _cachedEnabled;

  /// Поддерживается ли биометрия устройством и настроена ли хотя бы одна
  /// (отпечаток / лицо). false — если железа нет или ничего не записано.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return false;
      final types = await _auth.getAvailableBiometrics();
      return types.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    if (_cachedEnabled != null) return _cachedEnabled!;
    final v = await _storage.read(key: _enabledKey);
    return _cachedEnabled = v == 'true';
  }

  Future<void> setEnabled(bool value) async {
    _cachedEnabled = value;
    await _storage.write(key: _enabledKey, value: value.toString());
  }

  /// Показывает системный диалог биометрии. [reason] — пояснение для
  /// пользователя. Возвращает true при успехе.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // biometricOnly: false — допускаем PIN/паттерн как запасной вариант.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException {
      return false;
    }
  }
}
