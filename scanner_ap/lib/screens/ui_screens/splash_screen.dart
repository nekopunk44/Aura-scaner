import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import '../ui_screens/onboarding_screen.dart';
import '../../services/api_service.dart';
import '../../services/premium_service.dart';
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
    _navigateWithDelay();
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
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    bool isLoggedIn = false;
    try {
      await ApiService().syncBaseUrl();
      isLoggedIn = await ApiService().isLoggedIn();
      if (isLoggedIn) {
        await PremiumService().syncWithServer();
      }
    } catch (e) {
      debugPrint('Ошибка инициализации: $e');
    }
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final seenOnboarding = prefs.getBool(onboardingCompletedKey) ?? false;
    if (!mounted) return;

    // Онбординг показываем только незалогиненному пользователю при первом
    // запуске — у залогиненного он уже был, либо пропускаем (миграция со
    // старой версии без онбординга).
    final Widget next;
    if (isLoggedIn) {
      next = const MainScreen();
    } else if (!seenOnboarding) {
      next = const OnboardingScreen();
    } else {
      next = const LoginScreen();
    }

    // FadeTransition для контента, Hero сам анимирует логотип между
    // splash и login. Получается бесшовный переход: логотип «уезжает» в
    // финальную позицию, а вокруг него проявляются поля и кнопки.
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 700),
        reverseTransitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Color(0xFFEEF4FF),
              Color(0xFFF5F9FF),
              Colors.white,
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
                  child: const AuraLogo(size: 170),
                ),
                const SizedBox(height: 28),
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
                          'Aura Scanner',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Документы, OCR и AI в кармане',
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
