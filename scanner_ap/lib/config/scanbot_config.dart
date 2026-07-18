import 'package:flutter/foundation.dart';
import 'package:scanbot_sdk/scanbot_sdk.dart';

/// Centralized Scanbot initialization.
///
/// Keep the production license out of source control and provide it with:
/// `--dart-define=SCANBOT_LICENSE_KEY=<key>`.
class ScanbotConfig {
  ScanbotConfig._();

  static const String licenseKey = String.fromEnvironment(
    'SCANBOT_LICENSE_KEY',
  );

  static bool _initialized = false;
  static Object? _initializationError;

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (!isSupported || _initialized) return;

    try {
      await ScanbotSdk.initScanbotSdk(
        ScanbotSdkConfig(
          licenseKey: licenseKey,
          loggingEnabled: kDebugMode,
          enableNativeLogging: kDebugMode,
          storageImageQuality: 92,
        ),
      );
      _initialized = true;
      _initializationError = null;
    } catch (error, stackTrace) {
      _initializationError = error;
      debugPrint('Scanbot initialization failed: $error\n$stackTrace');
    }
  }

  static Future<void> ensureInitialized() async {
    await initialize();
    if (!isSupported) {
      throw UnsupportedError('Scanbot поддерживается только на Android и iOS');
    }
    if (!_initialized) {
      throw StateError(
        'Не удалось инициализировать Scanbot: '
        '${_initializationError ?? 'неизвестная ошибка'}',
      );
    }
  }
}
