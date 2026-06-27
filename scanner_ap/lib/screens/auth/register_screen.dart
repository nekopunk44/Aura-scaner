import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../widgets/auth_scaffold.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.register(
        name: _nameController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white54 : const Color(0xFF8A94A6);
    final inputFill = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF4F8FF);
    final inputBorder = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : const Color(0xFFD7E3F4);
    final prefixColor = isDark ? Colors.white54 : const Color(0xFF7D8FB0);
    final labelColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : const Color(0xFF8A94A6);
    final iconColor = isDark ? Colors.white : const Color(0xFF2CA5E0);

    return Scaffold(
      body: AuthBackground(
        isDark: isDark,
        child: SafeArea(
          child: Column(
            children: [
              // AppBar с центрированным заголовком
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: textColor,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Text(
                      l10n.registerTitle,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // Иконка с glow
                        Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF2CA5E0,
                                      ).withValues(alpha: isDark ? 0.30 : 0.18),
                                      blurRadius: 28,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isDark
                                        ? [
                                            const Color(
                                              0xFF2CA5E0,
                                            ).withValues(alpha: 0.22),
                                            const Color(
                                              0xFF7B61FF,
                                            ).withValues(alpha: 0.12),
                                          ]
                                        : [
                                            const Color(0xFFDCEBFF),
                                            const Color(0xFFEEF4FF),
                                          ],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(
                                      0xFF2CA5E0,
                                    ).withValues(alpha: isDark ? 0.45 : 0.30),
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.person_add_outlined,
                                  size: 36,
                                  color: iconColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          l10n.registerHeadline,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.registerSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: subtextColor),
                        ),

                        const SizedBox(height: 32),

                        AuthFormCard(
                          isDark: isDark,
                          padding: const EdgeInsets.all(22),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _Field(
                                  controller: _nameController,
                                  label: l10n.fieldName,
                                  icon: Icons.person_outline,
                                  textCapitalization: TextCapitalization.words,
                                  isDark: isDark,
                                  inputFill: inputFill,
                                  inputBorder: inputBorder,
                                  prefixColor: prefixColor,
                                  labelColor: labelColor,
                                  textColor: textColor,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return l10n.validateNameRequired;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _Field(
                                  controller: _emailController,
                                  label: l10n.fieldEmail,
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  isDark: isDark,
                                  inputFill: inputFill,
                                  inputBorder: inputBorder,
                                  prefixColor: prefixColor,
                                  labelColor: labelColor,
                                  textColor: textColor,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return l10n.validateEmailRequired;
                                    }
                                    if (!v.contains('@')) {
                                      return l10n.validateEmailInvalid;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _Field(
                                  controller: _passwordController,
                                  label: l10n.fieldPassword,
                                  icon: Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  isDark: isDark,
                                  inputFill: inputFill,
                                  inputBorder: inputBorder,
                                  prefixColor: prefixColor,
                                  labelColor: labelColor,
                                  textColor: textColor,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: prefixColor,
                                      size: 20,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return l10n.validatePasswordRequired;
                                    }
                                    if (v.length < 6) {
                                      return l10n.validatePasswordMin;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 22),
                                AuthPrimaryButton(
                                  isLoading: _isLoading,
                                  label: l10n.actionRegister,
                                  onPressed: _register,
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              l10n.registerHaveAccount,
                              style: TextStyle(
                                color: subtextColor,
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              ),
                              child: Text(
                                l10n.actionLogin,
                                style: const TextStyle(
                                  color: Color(0xFF2CA5E0),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final bool isDark;
  final Color inputFill;
  final Color inputBorder;
  final Color prefixColor;
  final Color labelColor;
  final Color textColor;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.inputFill,
    required this.inputBorder,
    required this.prefixColor,
    required this.labelColor,
    required this.textColor,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
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
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
