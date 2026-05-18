import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../utils/app_notification.dart';
import '../ui_screens/main_screen/app_tabs_screen.dart';

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
      AppNotification.show(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final prefixColor = isDark ? Colors.white54 : const Color(0xFFAAB4C8);
    final labelColor = isDark ? Colors.white.withValues(alpha: 0.5) : const Color(0xFF8A94A6);
    final iconBg = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFDCEBFF);
    final iconColor = isDark ? Colors.white : const Color(0xFF2CA5E0);

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
          child: Column(
            children: [
              // AppBar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: textColor, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Регистрация',
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),

                        // Icon
                        Center(
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
                            child: Icon(Icons.person_add_outlined,
                                size: 34, color: iconColor),
                          ),
                        ),

                        const SizedBox(height: 18),

                        Text(
                          'Создайте аккаунт',
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
                          'Заполните данные для регистрации',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: subtextColor),
                        ),

                        const SizedBox(height: 32),

                        // Form card
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: cardBorder, width: 1),
                            boxShadow: isDark
                                ? null
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                _Field(
                                  controller: _nameController,
                                  label: 'Имя',
                                  icon: Icons.person_outline,
                                  textCapitalization: TextCapitalization.words,
                                  isDark: isDark,
                                  inputFill: inputFill,
                                  inputBorder: inputBorder,
                                  prefixColor: prefixColor,
                                  labelColor: labelColor,
                                  textColor: textColor,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Введите имя';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _Field(
                                  controller: _emailController,
                                  label: 'Email',
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  isDark: isDark,
                                  inputFill: inputFill,
                                  inputBorder: inputBorder,
                                  prefixColor: prefixColor,
                                  labelColor: labelColor,
                                  textColor: textColor,
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return 'Введите email';
                                    if (!v.contains('@')) return 'Некорректный email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                _Field(
                                  controller: _passwordController,
                                  label: 'Пароль',
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
                                    onPressed: _isLoading ? null : _register,
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
                                        : const Text(
                                            'Зарегистрироваться',
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Уже есть аккаунт? ',
                                style: TextStyle(color: subtextColor, fontSize: 14)),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text(
                                'Войти',
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
