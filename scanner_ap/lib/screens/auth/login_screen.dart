import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../config/theme_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/social_auth_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../widgets/aura_logo.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import '../ui_screens/onboarding_screen.dart';
import '../ui_screens/splash_screen.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
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
      AppNotification.show(context, message: friendlyError(e));
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
      AppNotification.show(context, message: friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onGoogleTap() => _socialLogin(() => _socialAuth.loginWithGoogle(context));

  void _onAppleTap() => _socialLogin(_socialAuth.loginWithApple);

  void _onTelegramTap() async {
    setState(() => _isLoading = true);
    try {
      final user = await _socialAuth.loginWithTelegram(context);
      if (!mounted) return;
      if (user.email.contains('@telegram.placeholder')) {
        await _promptTelegramEmail();
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      AppNotification.show(context, message: friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _promptTelegramEmail() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();
    final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final inputFill = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F6FC);
    final inputBorder = isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE8EDF5);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.telegramAddEmailTitle,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
                const SizedBox(height: 8),
                Text(
                  l10n.telegramAddEmailBody,
                  style: TextStyle(fontSize: 13, color: subColor, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: textColor, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: TextStyle(color: subColor),
                    filled: true,
                    fillColor: inputFill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: scheme.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: subColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(l10n.actionSkip),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      ),
                      child: Text(l10n.actionAdd, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;
    final email = controller.text.trim();
    if (email.isEmpty || !email.contains('@')) return;
    try {
      await ApiService().dio.patch('/auth/profile', data: {'email': email});
    } catch (_) {
      // Некритично — пользователь может обновить email в настройках
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white54 : const Color(0xFF8A94A6);
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.white;
    final cardBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE8EDF5);
    final inputFill = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F6FC);
    final inputBorder = isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE8EDF5);
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

                  // Logo — tap to toggle theme. Hero обеспечивает плавный
                  // переход логотипа со splash на эту позицию. Никаких
                  // конкурирующих scale-анимаций вокруг — иначе они бы
                  // конфликтовали с интерполяцией Hero.
                  Center(
                    child: GestureDetector(
                      onTap: _toggleTheme,
                      child: Hero(
                        tag: kAuraLogoHeroTag,
                        child: const AuraLogo(size: 88),
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
                    child: Text(l10n.appName, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 6),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(fontSize: 14, color: subtextColor),
                    child: Text(l10n.loginSubtitle, textAlign: TextAlign.center),
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
                            label: l10n.fieldEmail,
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            isDark: isDark,
                            inputFill: inputFill,
                            inputBorder: inputBorder,
                            prefixColor: prefixColor,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return l10n.validateEmailRequired;
                              if (!v.contains('@')) return l10n.validateEmailInvalid;
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _AdaptiveTextField(
                            controller: _passwordController,
                            label: l10n.fieldPassword,
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
                              if (v == null || v.isEmpty) return l10n.validatePasswordRequired;
                              if (v.length < 6) return l10n.validatePasswordMin;
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
                                  : Text(l10n.actionLogin,
                                      style: const TextStyle(
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
                        child: Text(l10n.loginOrVia,
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
                          label: 'Telegram',
                          color: const Color(0xFF26A5E4),
                          faIcon: FontAwesomeIcons.telegram,
                          isDark: isDark,
                          labelColor: textColor,
                          onTap: _isLoading ? null : _onTelegramTap,
                        ),
                      ),
                    ],
                  ),

                  if (Platform.isIOS) ...[
                    const SizedBox(height: 12),
                    _SocialTile(
                      label: l10n.loginWithApple,
                      color: isDark ? Colors.white : Colors.black,
                      faIcon: FontAwesomeIcons.apple,
                      isDark: isDark,
                      labelColor: textColor,
                      onTap: _isLoading ? null : _onAppleTap,
                    ),
                  ],

                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.loginNoAccount,
                          style: TextStyle(color: subtextColor, fontSize: 14)),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen())),
                        child: Text(
                          l10n.actionRegister,
                          style: const TextStyle(
                              color: Color(0xFF2CA5E0),
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── DEV: preview onboarding ──────────────────────────
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OnboardingScreen(),
                        ),
                      ),
                      icon: Icon(
                        Icons.remove_red_eye_outlined,
                        size: 15,
                        color: subtextColor,
                      ),
                      label: Text(
                        'Preview Onboarding',
                        style: TextStyle(fontSize: 12, color: subtextColor),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
