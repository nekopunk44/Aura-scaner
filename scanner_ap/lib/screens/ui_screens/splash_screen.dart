import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import '../ui_screens/onboarding_screen.dart';
import '../../services/api_service.dart';
import '../../services/premium_service.dart';
import '../../services/biometric_service.dart';
import '../../widgets/aura_logo.dart';
import '../auth/login_screen.dart';

/// Hero-тег для бесшовного переноса логотипа между splash, login и
/// onboarding. Один и тот же логотип «приезжает» на нужное место
/// следующего экрана через Hero animation.
const String kAuraLogoHeroTag = 'aura-logo';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _textCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    // Запускаем чуть позже, чтобы логотип успел отрисоваться первым.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _textCtrl.forward();
    });
    _checkCameras();
    // _navigateWithDelay() читает AppLocalizations.of(context) синхронно в
    // начале — это dependOnInheritedWidgetOfExactType, и вызывать его прямо
    // в initState нельзя (в debug это ассерт «called before initState
    // completed», из-за которого splash зависал; в release ассерт вырезан,
    // поэтому APK работал). Откладываем до первого кадра, когда контекст
    // уже полностью смонтирован.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigateWithDelay();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _checkCameras() async {
    try {
      final cameras = await availableCameras();
      debugPrint('Доступно камер: ${cameras.length}');
    } catch (e) {
      debugPrint('Ошибка инициализации камер: $e');
    }
  }

  void _navigateWithDelay() async {
    // Вызывается из post-frame callback (см. initState), поэтому контекст
    // смонтирован и AppLocalizations.of(context) безопасен. Причину для
    // биометрии берём здесь, до первого await.
    if (!mounted) return;
    final biometricReason = AppLocalizations.of(context).biometricReason;
    // Инициализация (сеть, prefs) идёт ПАРАЛЛЕЛЬНО с анимацией логотипа.
    // Сплеш висит минимум 1.6 с, чтобы анимация успела отыграть, но не
    // ждёт фиксированные 3 с, как раньше: на быстрой сети холодный старт
    // сокращается почти вдвое, на медленной — не растёт сверх таймаута.
    final results = await Future.wait<Object?>([
      _resolveNextScreen(biometricReason),
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    if (!mounted) return;
    final next = results.first as Widget;

    // Не оборачиваем переход в FadeTransition: фон splash и фон login
    // — один и тот же LinearGradient, поэтому видимого «появления»
    // нового экрана быть не должно. Hero сам интерполирует положение
    // и размер логотипа поверх стабильного фона.
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, __, ___, child) => child,
        transitionDuration: const Duration(milliseconds: 800),
        reverseTransitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  /// Решает, какой экран показать после сплеша. Сетевая часть ограничена
  /// таймаутом — недоступный сервер не должен держать пользователя на
  /// сплеше дольше нескольких секунд.
  Future<Widget> _resolveNextScreen(String biometricReason) async {
    bool isLoggedIn = false;
    try {
      await ApiService().syncBaseUrl();
      isLoggedIn = await ApiService().isLoggedIn();
      if (isLoggedIn) {
        // Не довольствуемся наличием токена: проверяем сессию на сервере
        // (с авто-refresh внутри). Если сервер отверг — отправляем на логин.
        // Оффлайн validateSession вернёт true и пустит оптимистично.
        final valid = await ApiService()
            .validateSession()
            .timeout(const Duration(seconds: 8), onTimeout: () => true);
        if (!valid) {
          isLoggedIn = false;
        } else {
          await PremiumService()
              .syncWithServer()
              .timeout(const Duration(seconds: 5));
        }
      }
    } catch (e) {
      debugPrint('Ошибка инициализации: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool(onboardingCompletedKey) ?? false;

    // Онбординг показываем только незалогиненному пользователю при первом
    // запуске — у залогиненного он уже был, либо пропускаем (миграция со
    // старой версии без онбординга).
    if (isLoggedIn) {
      // Биометрический замок: если включён и доступен — требуем разблокировку
      // перед входом в приложение. При отказе/ошибке отправляем на логин
      // (токен в secure storage не трогаем — повторный вход по паролю вернёт
      // того же пользователя).
      if (await BiometricService().isEnabled() &&
          await BiometricService().isAvailable()) {
        final ok = await BiometricService().authenticate(biometricReason);
        if (!ok) return const LoginScreen();
      }
      return const MainScreen();
    }
    if (!seenOnboarding) return const OnboardingScreen();
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Цвета фона splash совпадают с фоном login_screen (тот же
    // LinearGradient в shell обоих экранов) — Hero логотип плывёт по
    // одному и тому же фоновому слою, без видимого скачка цвета.
    final gradient = isDark
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFD6E6F7),
              Color(0xFFDDEBF8),
              Color(0xFFE8F2FF),
            ],
          );
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor =
        isDark ? Colors.white.withValues(alpha: 0.7) : const Color(0xFF6B7A99);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hero оборачивает только SizedBox→AuraLogo: те же
                // параметры что и на login. Разница только в size —
                // Flutter сам интерполирует пропорцию между 170 и 88.
                Hero(
                  tag: kAuraLogoHeroTag,
                  child: const AuraLogo(size: 170, animate: true),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _textCtrl,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _textCtrl,
                      curve: Curves.easeOutCubic,
                    )),
                    child: Column(
                      children: [
                        Text(
                          l10n.appName,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.splashTagline,
                          style: TextStyle(
                            fontSize: 13,
                            color: subColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
