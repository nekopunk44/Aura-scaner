// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';

import '../../config/server_config.dart';
import '../../config/theme_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'premium_screen.dart';
import 'main_screen/remote_documents_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  String _serverUrl = '';
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _loadUrl();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    await ServerConfig().load();
    if (mounted) setState(() => _serverUrl = ServerConfig().baseUrl);
  }

  Future<void> _editServerUrl() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _serverUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => _ThemedDialog(
        isDark: isDark,
        title: 'Адрес сервера',
        content: _ThemedTextField(
          controller: controller,
          hint: 'http://192.168.x.x:3000/api',
          isDark: isDark,
          autofocus: true,
        ),
        actions: [
          _DialogButton(label: 'Отмена', onTap: () => Navigator.pop(ctx), isDark: isDark),
          _DialogButton(label: 'Сохранить', onTap: () => Navigator.pop(ctx, controller.text.trim()), isDark: isDark, primary: true),
        ],
      ),
    );
    if (newUrl == null || newUrl.isEmpty) return;
    try {
      await ServerConfig().save(newUrl);
      await ApiService().syncBaseUrl();
      if (mounted) setState(() => _serverUrl = ServerConfig().baseUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  void _showPresetsDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final presets = ServerConfig().presets;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        final subColor = isDark ? Colors.white38 : Colors.grey.shade500;
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text('Выберите адрес',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              ),
              ...presets.entries.map((e) => InkWell(
                onTap: () => Navigator.pop(ctx, e.value.isEmpty ? null : e.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                        if (e.value.isNotEmpty)
                          Text(e.value, style: TextStyle(fontSize: 12, color: subColor)),
                      ],
                    )),
                  ]),
                ),
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await ServerConfig().save(selected);
    await ApiService().syncBaseUrl();
    if (mounted) setState(() => _serverUrl = ServerConfig().baseUrl);
  }

  Future<void> _changePassword() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => _ThemedDialog(
          isDark: isDark,
          title: 'Смена пароля',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemedTextField(
                controller: currentCtrl,
                hint: 'Текущий пароль',
                isDark: isDark,
                obscure: obscureCurrent,
                suffix: IconButton(
                  icon: Icon(obscureCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent),
                ),
              ),
              const SizedBox(height: 12),
              _ThemedTextField(
                controller: newCtrl,
                hint: 'Новый пароль',
                isDark: isDark,
                obscure: obscureNew,
                suffix: IconButton(
                  icon: Icon(obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
                  onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                ),
              ),
            ],
          ),
          actions: [
            _DialogButton(label: 'Отмена', onTap: () => Navigator.pop(ctx, false), isDark: isDark),
            _DialogButton(label: 'Сохранить', onTap: () => Navigator.pop(ctx, true), isDark: isDark, primary: true),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final current = currentCtrl.text;
    final newPass = newCtrl.text;

    if (current.isEmpty || newPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните оба поля')),
      );
      return;
    }
    if (newPass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новый пароль — минимум 6 символов')),
      );
      return;
    }

    try {
      await AuthService().changePassword(currentPassword: current, newPassword: newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Пароль успешно изменён')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout_rounded, color: Colors.red, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  'Выйти из аккаунта?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
                ),
                const SizedBox(height: 8),
                Text(
                  'Вы уверены? Вам потребуется\nвойти снова.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: subColor, height: 1.45),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : const Color(0xFF6B7A99),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : const Color(0xFFDDE3ED),
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Отмена', style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: const Text('Выйти', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await AuthService().logout();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) {
            final glow = _pulseAnim.value;
            return Container(
              decoration: BoxDecoration(
                color: appBarBg,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2CA5E0).withValues(alpha: 0.04 + glow * 0.08),
                    blurRadius: 10 + glow * 8,
                    offset: const Offset(0, 3),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        bottom: 0,
                        left: 48,
                        right: 48,
                        child: Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF2CA5E0).withValues(alpha: 0.15 + glow * 0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Настройки',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Positioned(
                        left: 8,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(Icons.arrow_back_ios_new, size: 20, color: iconColor),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F1923), const Color(0xFF141E2B), const Color(0xFF0D1F30)]
                : [const Color(0xFFF2F6FC), const Color(0xFFEEF4FF), Colors.white],
          ),
        ),
        child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Градиентный заголовок
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2CA5E0), Color(0xFF1565C0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.document_scanner, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Aura Scanner',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('Версия 1.0.0',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
                  ],
                ),
                const Spacer(),
                // Переключатель темы прямо в баннере
                GestureDetector(
                  onTap: () => ThemeNotifier().toggle(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 420),
                    width: 56,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.25),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Stack(
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeInOut,
                          alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: Icon(
                                isDark ? Icons.dark_mode : Icons.light_mode,
                                size: 14,
                                color: isDark ? const Color(0xFF1A2A3F) : const Color(0xFF2CA5E0),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
          _Section(title: 'Сервисы', isDark: isDark, children: [
            _SettingsTile(
              icon: Icons.workspace_premium,
              iconColor: Colors.amber,
              title: 'Premium',
              subtitle: 'Открыть все возможности',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
              isDark: isDark,
            ),
            _SettingsTile(
              icon: Icons.cloud_outlined,
              iconColor: Colors.blue,
              title: 'Облако',
              subtitle: 'Документы на сервере',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemoteDocumentsScreen())),
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 12),
          _Section(title: 'Подключение', isDark: isDark, children: [
            _SettingsTile(
              icon: Icons.dns_outlined,
              iconColor: Colors.blue,
              title: 'Адрес сервера',
              subtitle: _serverUrl.isEmpty ? 'Не задан' : _serverUrl,
              onTap: _editServerUrl,
              isDark: isDark,
            ),
            _SettingsTile(
              icon: Icons.tune_outlined,
              iconColor: Colors.indigo,
              title: 'Готовые адреса',
              subtitle: 'Эмулятор, localhost, локальная сеть',
              onTap: _showPresetsDialog,
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 12),
          _Section(title: 'Аккаунт', isDark: isDark, children: [
            _SettingsTile(
              icon: Icons.lock_outline,
              iconColor: Colors.blue,
              title: 'Сменить пароль',
              onTap: _changePassword,
              isDark: isDark,
            ),
            _SettingsTile(
              icon: Icons.logout,
              iconColor: Colors.red,
              title: 'Выйти из аккаунта',
              titleColor: Colors.red,
              onTap: _logout,
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 12),
          _Section(title: 'О приложении', isDark: isDark, children: [
            _SettingsTile(
              icon: Icons.shield_outlined,
              iconColor: Colors.teal,
              title: 'Политика конфиденциальности',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
              isDark: isDark,
            ),
          ]),
          const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isDark;
  const _Section({required this.title, required this.children, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final headerColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 380),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: headerColor, letterSpacing: 0.8),
            child: Text(title.toUpperCase()),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2A3A) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isDark ? null : [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: children.asMap().entries.map((e) => Column(
              children: [
                e.value,
                if (e.key < children.length - 1)
                  Divider(height: 1, indent: 56, color: dividerColor),
              ],
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool isDark;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isDark,
    this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = titleColor ?? (isDark ? Colors.white : const Color(0xFF1A1A2E));
    final subColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final chevronColor = isDark ? Colors.white24 : Colors.grey.shade400;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: textColor)),
      subtitle: subtitle != null
          ? Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: subColor))
          : null,
      trailing: onTap != null ? Icon(Icons.chevron_right, color: chevronColor, size: 20) : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}

class _ThemedDialog extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget content;
  final List<Widget> actions;
  const _ThemedDialog({required this.isDark, required this.title, required this.content, required this.actions});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions.map((a) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: a,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool isDark;
  final bool obscure;
  final bool autofocus;
  final Widget? suffix;
  const _ThemedTextField({
    required this.controller, required this.hint, required this.isDark,
    this.obscure = false, this.autofocus = false, this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F6FC);
    final border = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE8EDF5);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final hintColor = isDark ? Colors.white38 : Colors.grey.shade400;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        suffixIcon: suffix,
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5)),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool primary;
  const _DialogButton({required this.label, required this.onTap, required this.isDark, this.primary = false});

  @override
  Widget build(BuildContext context) {
    if (primary) {
      const bg = Color(0xFF2CA5E0);
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white54 : Colors.grey.shade600,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label),
    );
  }
}

