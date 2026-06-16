import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'l10n/app_localizations.dart';
import 'screens/ui_screens/splash_screen.dart';
import 'services/deep_link_service.dart';
import 'services/premium_service.dart';
import 'config/sentry_config.dart';
import 'config/theme_config.dart';
import 'config/locale_config.dart';
import 'widgets/app_lock_guard.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  await bootstrapSentry(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Инициализация pdfrx (настройка pdfium + каталог кэша). Виджеты pdfrx
    // делают это сами, но прямые вызовы PdfDocument.openFile (превью,
    // PDF→JPEG, сжатие/слияние) — нет, и без этого падали с
    // StateError: Pdfrx.getCacheDirectory not set.
    // dismissPdfiumWasmWarnings: убирает debug-предупреждение pdfrx о
    // бандлинге PDFium WASM (~4 МБ). На мобиле WASM не используется в
    // рантайме; для нас это лишь шум в консоли.
    pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
    DeepLinkService().init();
    await ThemeNotifier().load();
    await LocaleNotifier().load();
    await PremiumService().load();
    runApp(const ScannerApp());
  });
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Перерисовываем при смене и темы, и языка.
      listenable: Listenable.merge([ThemeNotifier(), LocaleNotifier()]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeNotifier().mode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeOut,
          // Локализация: ru — основной язык, en — перевод. locale=null →
          // язык по системной локали устройства; иначе — выбор пользователя
          // из настроек. ru первый в supportedLocales — fallback по умолчанию.
          locale: LocaleNotifier().locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: const [Locale('ru'), Locale('en')],
          home: const SplashScreen(),
          builder: (context, child) => AppLockGuard(
            navigatorKey: appNavigatorKey,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
