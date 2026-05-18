import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _socialAuth = SocialAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  int _logoTapCount = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() => _logoTapCount++);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onGoogleTap() => _socialLogin(_socialAuth.loginWithGoogle);
  void _onVkTap() => _socialLogin(_socialAuth.loginWithVk);
  void _onTelegramTap() => _socialLogin(() => _socialAuth.loginWithTelegram(context));

  void _onInstagramTap() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Instagram: замените YOUR_INSTAGRAM_APP_ID в SocialAuthService'),
      duration: Duration(seconds: 4),
      backgroundColor: Color(0xFFE1306C),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white54 : const Color(0xFF8A94A6);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE8EDF5);
    final inputFill = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F6FC);
    final inputBorder = isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE8EDF5);
    final iconBg = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFDCEBFF);
    final iconColor = isDark ? Colors.white : const Color(0xFF2CA5E0);
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFDDE3ED);
    final prefixColor = isDark ? Colors.white54 : const Color(0xFFAAB4C8);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1a1a2e), const Color(0xFF16213e), const Color(0xFF0f3460)]
                : [const Color(0xFFEEF4FF), const Color(0xFFF5F9FF), Colors.white],
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

                  // Logo — tap to toggle theme
                  Center(
                    child: GestureDetector(
                      onTap: _toggleTheme,
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(_logoTapCount),
                        tween: Tween(begin: 0.82, end: 1.0),
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.elasticOut,
                        builder: (context, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
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

                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 0.5,
                    ),
                    child: const Text('Aura Scanner', textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(fontSize: 14, color: subtextColor),
                    child: const Text('Войдите в свой аккаунт', textAlign: TextAlign.center),
                  ),

                  const SizedBox(height: 36),

                  // Form card
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cardBorder, width: 1),
                      boxShadow: isDark
                          ? null
                          : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4))],
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
                            isDark: isDark,
                            inputFill: inputFill,
                            inputBorder: inputBorder,
                            prefixColor: prefixColor,
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
                            isDark: isDark,
                            inputFill: inputFill,
                            inputBorder: inputBorder,
                            prefixColor: prefixColor,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: prefixColor,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
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
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Войти',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  Row(
                    children: [
                      Expanded(child: Divider(color: dividerColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text('или войдите через',
                            style: TextStyle(fontSize: 12, color: subtextColor)),
                      ),
                      Expanded(child: Divider(color: dividerColor)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: _SocialTile(
                          label: 'Google',
                          color: const Color(0xFFEA4335),
                          faIcon: FontAwesomeIcons.google,
                          isDark: isDark,
                          labelColor: textColor,
                          onTap: _isLoading ? null : _onGoogleTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SocialTile(
                          label: 'ВКонтакте',
                          color: const Color(0xFF0077FF),
                          faIcon: FontAwesomeIcons.vk,
                          isDark: isDark,
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
                          faIcon: FontAwesomeIcons.telegram,
                          isDark: isDark,
                          labelColor: textColor,
                          onTap: _isLoading ? null : _onTelegramTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SocialTile(
                          label: 'Instagram',
                          color: const Color(0xFFE1306C),
                          faIcon: FontAwesomeIcons.instagram,
                          isDark: isDark,
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
                      Text('Нет аккаунта? ',
                          style: TextStyle(color: subtextColor, fontSize: 14)),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen())),
                        child: const Text(
                          'Зарегистрироваться',
                          style: TextStyle(
                              color: Color(0xFF2CA5E0),
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
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
  }
}

class _AdaptiveTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final bool isDark;
  final Color inputFill;
  final Color inputBorder;
  final Color prefixColor;

  const _AdaptiveTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.inputFill,
    required this.inputBorder,
    required this.prefixColor,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF8A94A6);

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(color: textColor, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: labelColor, fontSize: 14),
        prefixIcon: Icon(icon, size: 20, color: prefixColor),
        suffixIcon: suffix,
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: inputBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  final String label;
  final Color color;
  final IconData faIcon;
  final bool isDark;
  final Color labelColor;
  final VoidCallback? onTap;

  const _SocialTile({
    required this.label,
    required this.color,
    required this.faIcon,
    required this.isDark,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE8EDF5),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: color.withValues(alpha: 0.12),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(faIcon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: labelColor,
                        fontWeight: FontWeight.w500,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
