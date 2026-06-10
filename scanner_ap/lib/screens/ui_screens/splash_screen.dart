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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF8CDDFF),
              Color(0xFF2CA5E0),
              Color(0xFF0D47A1),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Hero(
                  tag: kAuraLogoHeroTag,
                  child: const AuraLogo(size: 170, monoWhite: true),
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
                        const Text(
                          'Aura Scanner',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Документы, OCR и AI в кармане',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
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
