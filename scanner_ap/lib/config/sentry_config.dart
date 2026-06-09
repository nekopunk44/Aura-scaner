import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// DSN передаётся через --dart-define=SENTRY_DSN=... при сборке релиза.
/// Пустая строка — Sentry не инициализируется (dev-сборки без DSN
/// продолжают работать как раньше, ошибки идут в обычный консольный лог).
const _sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

bool get isSentryEnabled => _sentryDsn.isNotEmpty;

/// Запускает приложение под Sentry, если DSN сконфигурирован. Иначе
/// просто вызывает [appRunner] напрямую — без оверхеда.
Future<void> bootstrapSentry(Future<void> Function() appRunner) async {
  if (!isSentryEnabled) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (options) {
      options.dsn = _sentryDsn;
      options.environment = kReleaseMode ? 'production' : 'development';
      // 10% — баланс между видимостью узких мест и квотой проекта.
      options.tracesSampleRate = kReleaseMode ? 0.1 : 1.0;
      options.attachScreenshot = false;
      options.sendDefaultPii = false;
    },
    appRunner: appRunner,
  );
}
