import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../config/theme_config.dart';
import '../../services/auth_service.dart';
import '../../services/social_auth_service.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _socialAuth = SocialAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  late AnimationController _logoController;
  late AnimationController _themeController;
  late Animation<double> _spinAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _themeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: ThemeNotifier().isDark ? 1.0 : 0.0,
    );

    _spinAnim = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOut),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 35),
    ]).animate(CurvedAnimation(parent: _logoController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _logoController.dispose();
    _themeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    if (_logoController.isAnimating) return;
    _logoController.forward(from: 0);
    if (ThemeNotifier().isDark) {
      _themeController.reverse();
    } else {
      _themeController.forward();
    }
    ThemeNotifier().toggle();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _socialLogin(Future<AuthUser> Function() authCall) async {
    setState(() => _isLoading = true);
    try {
      await authCall();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onGoogleTap() => _socialLogin(_socialAuth.loginWithGoogle);
  void _onVkTap() => _socialLogin(_socialAuth.loginWithVk);
  void _onTelegramTap() => _socialLogin(() => _socialAuth.loginWithTelegram(context));

  void _onInstagramTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Instagram: замените YOUR_INSTAGRAM_APP_ID в SocialAuthService '
          'и добавьте обмен кодом на backend',
        ),
        duration: Duration(seconds: 4),
        backgroundColor: Color(0xFFE1306C),
      ),
    );
  }

  // ── light palette ──────────────────────────────────────────────────────────
  static const _lightBg1 = Color(0xFFEEF4FF);
  static const _lightBg2 = Color(0xFFF5F9FF);
  static const _lightBg3 = Color(0xFFFFFFFF);
  static const _lightText = Color(0xFF1A1A2E);
  static const _lightSubtext = Color(0xFF8A94A6);
  static const _lightCard = Colors.white;
  static const _lightCardBorder = Color(0xFFE8EDF5);
  static const _lightInputFill = Color(0xFFF2F6FC);

  // ── dark palette ───────────────────────────────────────────────────────────
  static const _darkBg1 = Color(0xFF1a1a2e);
  static const _darkBg2 = Color(0xFF16213e);
  static const _darkBg3 = Color(0xFF0f3460);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeController,
      builder: (context, child) {
        final t = _themeController.value;

        final bg1 = Color.lerp(_lightBg1, _darkBg1, t)!;
        final bg2 = Color.lerp(_lightBg2, _darkBg2, t)!;
        final bg3 = Color.lerp(_lightBg3, _darkBg3, t)!;
        final textColor = Color.lerp(_lightText, Colors.white, t)!;
        final subtextColor = Color.lerp(_lightSubtext, Colors.white54, t)!;
        final cardBg = Color.lerp(_lightCard, Colors.white.withValues(alpha: 0.07), t)!;
        final cardBorder = Color.lerp(_lightCardBorder, Colors.white.withValues(alpha: 0.12), t)!;
        final inputFill = Color.lerp(_lightInputFill, Colors.white.withValues(alpha: 0.07), t)!;
        final inputBorder = Color.lerp(_lightCardBorder, Colors.white.withValues(alpha: 0.15), t)!;
        final iconBg = Color.lerp(const Color(0xFFDCEBFF), Colors.white.withValues(alpha: 0.12), t)!;
        final iconColor = Color.lerp(const Color(0xFF2CA5E0), Colors.white, t)!;
        final dividerColor = Color.lerp(const Color(0xFFDDE3ED), Colors.white.withValues(alpha: 0.15), t)!;
        final tileColor = Color.lerp(_lightCard, Colors.white.withValues(alpha: 0.07), t)!;
        final tileBorder = Color.lerp(_lightCardBorder, Colors.white.withValues(alpha: 0.12), t)!;
        final labelColor = Color.lerp(const Color(0xFF8A94A6), Colors.white.withValues(alpha: 0.5), t)!;
        final prefixIconColor = Color.lerp(const Color(0xFFAAB4C8), Colors.white54, t)!;
        final registerLinkColor = Color.lerp(const Color(0xFF2CA5E0), const Color(0xFF2CA5E0), t)!;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg1, bg2, bg3],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),

                      // Logo with tap-to-toggle-theme animation
                      Center(
                        child: GestureDetector(
                          onTap: _toggleTheme,
                          child: AnimatedBuilder(
                            animation: _logoController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _scaleAnim.value,
                                child: Transform.rotate(
                                  angle: _spinAnim.value,
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: iconBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: iconColor.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.document_scanner,
                                size: 36,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Text(
                        'Aura Scanner',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Войдите в свой аккаунт',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: subtextColor),
                      ),

                      const SizedBox(height: 36),

                      // Form card
                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cardBorder, width: 1),
                          boxShadow: t < 0.5
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06 * (1 - t * 2)),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _AdaptiveTextField(
                                controller: _emailController,
                                label: 'Email',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textColor: textColor,
                                labelColor: labelColor,
                                prefixIconColor: prefixIconColor,
                                inputFill: inputFill,
                                inputBorder: inputBorder,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Введите email';
                                  if (!v.contains('@')) return 'Некорректный email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              _AdaptiveTextField(
                                controller: _passwordController,
                                label: 'Пароль',
                                icon: Icons.lock_outline,
                                obscureText: _obscurePassword,
                                textColor: textColor,
                                labelColor: labelColor,
                                prefixIconColor: prefixIconColor,
                                inputFill: inputFill,
                                inputBorder: inputBorder,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: prefixIconColor,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Введите пароль';
                                  if (v.length < 6) return 'Минимум 6 символов';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2CA5E0),
                                    disabledBackgroundColor:
                                        const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text(
                                          'Войти',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: dividerColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'или войдите через',
                              style: TextStyle(fontSize: 12, color: subtextColor),
                            ),
                          ),
                          Expanded(child: Divider(color: dividerColor)),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Social grid
                      Row(
                        children: [
                          Expanded(
                            child: _SocialTile(
                              label: 'Google',
                              color: const Color(0xFFEA4335),
                              icon: Icons.g_mobiledata_rounded,
                              tileColor: tileColor,
                              tileBorder: tileBorder,
                              labelColor: textColor,
                              onTap: _isLoading ? null : _onGoogleTap,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialTile(
                              label: 'ВКонтакте',
                              color: const Color(0xFF0077FF),
                              icon: Icons.people_alt_outlined,
                              tileColor: tileColor,
                              tileBorder: tileBorder,
                              labelColor: textColor,
                              onTap: _isLoading ? null : _onVkTap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _SocialTile(
                              label: 'Telegram',
                              color: const Color(0xFF26A5E4),
                              icon: Icons.send_outlined,
                              tileColor: tileColor,
                              tileBorder: tileBorder,
                              labelColor: textColor,
                              onTap: _isLoading ? null : _onTelegramTap,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialTile(
                              label: 'Instagram',
                              color: const Color(0xFFE1306C),
                              icon: Icons.camera_alt_outlined,
                              tileColor: tileColor,
                              tileBorder: tileBorder,
                              labelColor: textColor,
                              onTap: _isLoading ? null : _onInstagramTap,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 32),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Нет аккаунта? ',
                            style: TextStyle(color: subtextColor, fontSize: 14),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen()),
                            ),
                            child: Text(
                              'Зарегистрироваться',
                              style: TextStyle(
                                color: registerLinkColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _AdaptiveTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final Color textColor;
  final Color labelColor;
  final Color prefixIconColor;
  final Color inputFill;
  final Color inputBorder;

  const _AdaptiveTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.textColor,
    required this.labelColor,
    required this.prefixIconColor,
    required this.inputFill,
    required this.inputBorder,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(color: textColor, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: labelColor, fontSize: 14),
        prefixIcon: Icon(icon, size: 20, color: prefixIconColor),
        suffixIcon: suffix,
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final Color tileColor;
  final Color tileBorder;
  final Color labelColor;
  final VoidCallback? onTap;

  const _SocialTile({
    required this.label,
    required this.color,
    required this.icon,
    required this.tileColor,
    required this.tileBorder,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: color.withValues(alpha: 0.12),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tileBorder, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
