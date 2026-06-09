import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import '../../services/api_service.dart';
import '../../services/premium_service.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkCameras();
    _navigateWithDelay();
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

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            isLoggedIn ? const MainScreen() : const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: Curves.easeInOut));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color.fromARGB(255, 15, 15, 15),
      body: Center(
        child: SizedBox(
          height: 90,
          width: 90,
          child: FlutterLogo(size: 90),
        ),
      ),
    );
  }
}
