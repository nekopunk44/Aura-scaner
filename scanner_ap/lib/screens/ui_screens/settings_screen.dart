// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/server_config.dart';
import '../../config/theme_config.dart';
import '../../config/locale_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/social_auth_service.dart';
import '../../services/premium_service.dart';
import '../../services/biometric_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/app_notification.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_screen.dart';
import 'premium_screen.dart';
import 'main_screen/remote_documents_screen.dart';
import 'privacy_policy_screen.dart';
import 'session_management_screen.dart';
import 'signature/home_screen.dart' as signature;
import 'translate/translation_models_screen.dart';

bool _isSyntheticEmail(String email) =>
    email.startsWith('tg_') || email.contains('@telegram') || email.contains('@telegr');

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  String _serverUrl = '';
  String _version = '';
  AuthUser? _user;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _introCtrl;

  @override
  void initState() {
    super.initState();
    _loadUrl();
    _loadProfile();
    _loadVersion();
    _loadBiometric();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _introCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    await ServerConfig().load();
    if (mounted) setState(() => _serverUrl = ServerConfig().baseUrl);
  }

  Future<void> _loadProfile() async {
    final user = await AuthService().getProfile();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _version = '${info.version} (${info.buildNumber})');
    }
  }

  Future<void> _loadBiometric() async {
    final available = await BiometricService().isAvailable();
    final enabled = await BiometricService().isEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  /// Включение биометрии требует успешной проверки прямо сейчас — иначе
  /// пользователь рискует заблокировать себя нерабочим сенсором.
  Future<void> _toggleBiometric(bool value) async {
    final l10n = AppLocalizations.of(context);
    if (value) {
      final ok = await BiometricService().authenticate(l10n.biometricReason);
      if (!ok) return;
    }
    await BiometricService().setEnabled(value);
    if (mounted) setState(() => _biometricEnabled = value);
  }

  String _languageName(AppLocalizations l10n) {
    final code = LocaleNotifier().locale?.languageCode;
    return switch (code) {
      'ru' => l10n.langRussian,
      'en' => l10n.langEnglish,
      _ => l10n.langSystem,
    };
  }

  Future<void> _showLanguageDialog() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final current = LocaleNotifier().locale?.languageCode;

    final options = <(String?, String)>[
      (null, l10n.langSystem),
      ('ru', l10n.langRussian),
      ('en', l10n.langEnglish),
    ];

    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                l10n.settingsLanguage,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            for (final (code, label) in options)
              InkWell(
                onTap: () => Navigator.pop(ctx, code ?? '__system__'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(color: textColor, fontSize: 15),
                        ),
                      ),
                      if (code == current)
                        const Icon(
                          Icons.check,
                          color: Color(0xFF2CA5E0),
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await LocaleNotifier().setLocale(
      selected == '__system__' ? null : Locale(selected),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editProfile() async {
    if (_user == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    // Вычисляем полный URL аватара здесь, до открытия листа,
    // чтобы контекст был корректным.
    final raw = _user!.avatarUrl?.trim();
    String? resolvedUrl;
    if (raw != null && raw.isNotEmpty) {
      final uri = Uri.tryParse(raw);
      if (uri != null && uri.hasScheme) {
        resolvedUrl = raw;
      } else {
        final base = Uri.tryParse(ServerConfig().baseUrl);
        resolvedUrl = base?.resolve(raw).toString() ?? raw;
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => _EditProfileSheet(
        user: _user!,
        initials: _initials,
        resolvedAvatarUrl: resolvedUrl,
        isDark: isDark,
        l10n: l10n,
        onSaved: (updated) {
          if (mounted) {
            setState(() => _user = updated);
            AppNotification.show(
              context,
              message: l10n.profileSaved,
              type: NotificationType.success,
            );
          }
        },
      ),
    );
  }

  /// Каскадное появление блоков: каждый следующий стартует чуть позже,
  /// с fade + лёгким подъёмом снизу.
  Widget _staggered(int index, Widget child) {
    final anim = CurvedAnimation(
      parent: _introCtrl,
      curve: Interval(
        (0.1 * index).clamp(0.0, 0.6),
        1.0,
        curve: Curves.easeOutCubic,
      ),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
    );
  }

  String get _initials {
    final name = _user?.name.trim() ?? '';
    if (name.isEmpty) return '';
    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final first = parts.first.characters.first;
    final second = parts.length > 1 ? parts[1].characters.first : '';
    return (first + second).toUpperCase();
  }

  Future<void> _editServerUrl() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: _serverUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (ctx) => _ThemedDialog(
        isDark: isDark,
        title: l10n.settingsServerAddress,
        content: _ThemedTextField(
          controller: controller,
          hint: 'http://192.168.x.x:3000/api',
          isDark: isDark,
          autofocus: true,
        ),
        actions: [
          _DialogButton(
            label: l10n.actionCancel,
            onTap: () => Navigator.pop(ctx),
            isDark: isDark,
          ),
          _DialogButton(
            label: l10n.actionSave,
            onTap: () => Navigator.pop(ctx, controller.text.trim()),
            isDark: isDark,
            primary: true,
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  void _showPresetsDialog() async {
    final l10n = AppLocalizations.of(context);
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  l10n.settingsPresetsTitle,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              ...presets.entries.map(
                (e) => InkWell(
                  onTap: () =>
                      Navigator.pop(ctx, e.value.isEmpty ? null : e.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.key,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              if (e.value.isNotEmpty)
                                Text(
                                  e.value,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: subColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
    final l10n = AppLocalizations.of(context);
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
          title: l10n.settingsChangePasswordTitle,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ThemedTextField(
                controller: currentCtrl,
                hint: l10n.settingsCurrentPassword,
                isDark: isDark,
                obscure: obscureCurrent,
                suffix: IconButton(
                  icon: Icon(
                    obscureCurrent
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  onPressed: () =>
                      setDialogState(() => obscureCurrent = !obscureCurrent),
                ),
              ),
              const SizedBox(height: 12),
              _ThemedTextField(
                controller: newCtrl,
                hint: l10n.settingsNewPassword,
                isDark: isDark,
                obscure: obscureNew,
                suffix: IconButton(
                  icon: Icon(
                    obscureNew
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                  ),
                  onPressed: () =>
                      setDialogState(() => obscureNew = !obscureNew),
                ),
              ),
            ],
          ),
          actions: [
            _DialogButton(
              label: l10n.actionCancel,
              onTap: () => Navigator.pop(ctx, false),
              isDark: isDark,
            ),
            _DialogButton(
              label: l10n.actionSave,
              onTap: () => Navigator.pop(ctx, true),
              isDark: isDark,
              primary: true,
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final current = currentCtrl.text;
    final newPass = newCtrl.text;

    if (current.isEmpty || newPass.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsFillBothFields)));
      return;
    }
    if (newPass.length < 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.settingsNewPasswordMin)));
      return;
    }

    try {
      await AuthService().changePassword(
        currentPassword: current,
        newPassword: newPass,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.settingsPasswordChanged)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final bg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.settingsLogoutConfirmTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsLogoutConfirmBody,
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
                          foregroundColor: isDark
                              ? Colors.white70
                              : const Color(0xFF6B7A99),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFDDE3ED),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(
                          l10n.actionCancel,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        child: Text(
                          l10n.actionLogout,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final iconColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F1923)
          : const Color(0xFFE8EFF9),
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
                    color: const Color(
                      0xFF2CA5E0,
                    ).withValues(alpha: 0.04 + glow * 0.08),
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
                                const Color(
                                  0xFF2CA5E0,
                                ).withValues(alpha: 0.15 + glow * 0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        l10n.settingsTitle,
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
                              child: Icon(
                                Icons.arrow_back_ios_new,
                                size: 20,
                                color: iconColor,
                              ),
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
                ? [
                    const Color(0xFF0F1923),
                    const Color(0xFF141E2B),
                    const Color(0xFF0D1F30),
                  ]
                : [
                    const Color(0xFFE4ECF8),
                    const Color(0xFFE8EFF9),
                    const Color(0xFFEDF4FF),
                  ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Шапка-профиль: аватар с инициалами, имя, email и статус подписки.
            // Пока профиль не загрузился (или нет сети) — фолбэк с брендом.
            _staggered(
              0,
              _ProfileHeaderCard(
                user: _user,
                initials: _initials,
                l10n: l10n,
                isPremium: PremiumService().isPremium,
                onEdit: _user == null ? null : _editProfile,
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // ── Безопасность ──────────────────────────────────────────
                  _staggered(
                    1,
                    _Section(
                      title: l10n.secSectionSecurity,
                      isDark: isDark,
                      children: [
                        _SettingsTile(
                          icon: Icons.fingerprint,
                          iconColor: const Color(0xFF26C060),
                          title: l10n.secBiometricTitle,
                          subtitle: _biometricAvailable
                              ? l10n.secBiometricSubtitle
                              : l10n.secBiometricUnavailable,
                          isDark: isDark,
                          trailing: Switch.adaptive(
                            value: _biometricEnabled,
                            activeThumbColor: const Color(0xFF2CA5E0),
                            onChanged: _biometricAvailable
                                ? _toggleBiometric
                                : null,
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.lock_outline,
                          iconColor: Colors.blue,
                          title: l10n.settingsChangePasswordTile,
                          onTap: _changePassword,
                          isDark: isDark,
                        ),
                        _SettingsTile(
                          icon: Icons.devices_outlined,
                          iconColor: const Color(0xFF2CA5E0),
                          title: l10n.settingsActiveSessions,
                          subtitle: l10n.settingsActiveSessionsSub,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SessionManagementScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Приложение ────────────────────────────────────────────
                  _staggered(
                    2,
                    _Section(
                      title: l10n.secSectionApp,
                      isDark: isDark,
                      children: [
                        _SettingsTile(
                          icon: isDark ? Icons.dark_mode : Icons.light_mode,
                          iconColor: Colors.indigo,
                          title: l10n.settingsTheme,
                          subtitle: isDark
                              ? l10n.settingsThemeDark
                              : l10n.settingsThemeLight,
                          isDark: isDark,
                          trailing: Switch.adaptive(
                            value: isDark,
                            activeThumbColor: const Color(0xFF2CA5E0),
                            onChanged: (_) => ThemeNotifier().toggle(),
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.language,
                          iconColor: Colors.teal,
                          title: l10n.settingsLanguage,
                          subtitle: _languageName(l10n),
                          onTap: _showLanguageDialog,
                          isDark: isDark,
                        ),
                        _SettingsTile(
                          icon: Icons.translate,
                          iconColor: Colors.deepPurple,
                          title: l10n.settingsTranslateModels,
                          subtitle: l10n.settingsTranslateModelsSub,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TranslationModelsScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Сервисы ───────────────────────────────────────────────
                  _staggered(
                    3,
                    _Section(
                      title: l10n.settingsSectionServices,
                      isDark: isDark,
                      children: [
                        _SettingsTile(
                          icon: Icons.workspace_premium,
                          iconColor: Colors.amber,
                          title: 'Premium',
                          subtitle: l10n.settingsPremiumSubtitle,
                          badge: const _ProBadge(),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PremiumScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                        _SettingsTile(
                          icon: Icons.cloud_outlined,
                          iconColor: Colors.blue,
                          title: l10n.settingsCloud,
                          subtitle: l10n.settingsCloudSubtitle,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RemoteDocumentsScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                        _SettingsTile(
                          icon: Icons.draw_outlined,
                          iconColor: Colors.teal,
                          title: l10n.featSignature,
                          subtitle: l10n.featSignatureSub,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const signature.HomeScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Выбор сервера — инструмент разработки: в релизной сборке скрыт.
                  if (kDebugMode) ...[
                    _staggered(
                      4,
                      _Section(
                        title: l10n.settingsSectionConnectionDebug,
                        isDark: isDark,
                        children: [
                          _SettingsTile(
                            icon: Icons.dns_outlined,
                            iconColor: Colors.blue,
                            title: l10n.settingsServerAddress,
                            subtitle: _serverUrl.isEmpty
                                ? l10n.settingsNotSet
                                : _serverUrl,
                            onTap: _editServerUrl,
                            isDark: isDark,
                          ),
                          _SettingsTile(
                            icon: Icons.tune_outlined,
                            iconColor: Colors.indigo,
                            title: l10n.settingsPresets,
                            subtitle: l10n.settingsPresetsSubtitle,
                            onTap: _showPresetsDialog,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── О приложении ──────────────────────────────────────────
                  _staggered(
                    5,
                    _Section(
                      title: l10n.settingsSectionAbout,
                      isDark: isDark,
                      children: [
                        _SettingsTile(
                          icon: Icons.shield_outlined,
                          iconColor: Colors.teal,
                          title: l10n.settingsPrivacyPolicy,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen(),
                            ),
                          ),
                          isDark: isDark,
                        ),
                        _SettingsTile(
                          icon: Icons.info_outline,
                          iconColor: Colors.blueGrey,
                          title: l10n.settingsVersion,
                          subtitle: _version.isEmpty ? '—' : _version,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Выход (отдельной карточкой, акцент красным) ────────────
                  _staggered(
                    6,
                    _Section(
                      title: l10n.settingsSectionAccount,
                      isDark: isDark,
                      children: [
                        _SettingsTile(
                          icon: Icons.logout,
                          iconColor: Colors.red,
                          title: l10n.settingsLogout,
                          titleColor: Colors.red,
                          onTap: _logout,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
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
  const _Section({
    required this.title,
    required this.children,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final headerColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.grey.shade100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 380),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: headerColor,
              letterSpacing: 0.8,
            ),
            child: Text(title.toUpperCase()),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2A3A) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            children: children
                .asMap()
                .entries
                .map(
                  (e) => Column(
                    children: [
                      e.value,
                      if (e.key < children.length - 1)
                        Divider(height: 1, indent: 56, color: dividerColor),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// Карточка профиля с фоном из аватара и бейджем социального провайдера.
class _ProfileHeaderCard extends StatelessWidget {
  final AuthUser? user;
  final String initials;
  final AppLocalizations l10n;
  final bool isPremium;
  final VoidCallback? onEdit;

  const _ProfileHeaderCard({
    required this.user,
    required this.initials,
    required this.l10n,
    required this.isPremium,
    required this.onEdit,
  });

  String get _provider => (user?.provider ?? '').toLowerCase();

  String? get _imageUrl {
    final raw = user?.avatarUrl?.trim();
    if (raw == null || raw.isEmpty) return null;

    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) return raw;

    final base = Uri.tryParse(ServerConfig().baseUrl);
    if (base == null) return raw;
    return base.resolve(raw).toString();
  }

  bool get _isTelegram {
    final email = user?.email.toLowerCase() ?? '';
    final imageUrl = _imageUrl?.toLowerCase() ?? '';
    return _provider.contains('telegram') ||
        email.contains('@telegram.placeholder') ||
        imageUrl.contains('telegram');
  }

  bool get _isGoogle {
    final imageUrl = _imageUrl?.toLowerCase() ?? '';
    return _provider.contains('google') ||
        imageUrl.contains('googleusercontent');
  }

  IconData? get _providerIcon {
    if (_isTelegram) return FontAwesomeIcons.telegram;
    if (_isGoogle) return FontAwesomeIcons.google;
    return null;
  }

  Color get _providerAccent {
    if (_isTelegram) return const Color(0xFF2AABEE);
    if (_isGoogle) return const Color(0xFF4285F4);
    return const Color(0xFF2CA5E0);
  }

  List<Color> get _fallbackColors {
    if (_isTelegram) {
      return const [Color(0xFF37AEE2), Color(0xFF1E7BD8)];
    }
    if (_isGoogle) {
      return const [Color(0xFF4285F4), Color(0xFF1565C0)];
    }
    return const [Color(0xFF2CA5E0), Color(0xFF1565C0)];
  }

  Widget _fallbackBackground() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _fallbackColors,
        ),
      ),
    );
  }

  Widget _photoBackground(String imageUrl) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.18,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackBackground(),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _fallbackColors.first.withValues(alpha: 0.76),
                _fallbackColors.last.withValues(alpha: 0.66),
              ],
            ),
          ),
        ),
        ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
      ],
    );
  }

  Widget _avatarFallback() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.36),
            Colors.white.withValues(alpha: 0.14),
          ],
        ),
      ),
      child: initials.isEmpty
          ? const Icon(Icons.document_scanner, color: Colors.white, size: 26)
          : Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  Widget _avatar() {
    final imageUrl = _imageUrl;
    final providerIcon = _providerIcon;

    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.50),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipOval(
                child: imageUrl == null
                    ? _avatarFallback()
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(),
                      ),
              ),
            ),
          ),
          if (providerIcon != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: FaIcon(providerIcon, color: _providerAccent, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _imageUrl;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _providerAccent.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: imageUrl == null
                  ? _fallbackBackground()
                  : _photoBackground(imageUrl),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.10),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                children: [
                  _avatar(),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user == null) ...[
                          Container(
                            width: 130,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ] else
                          Text(
                            user!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (user == null) ...[
                          Container(
                            width: 180,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ] else if (_isSyntheticEmail(user!.email)) ...[
                          // синтетический email (tg_…@telegr…) — не показываем
                        ] else
                          Text(
                            user!.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.76),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        const SizedBox(height: 8),
                        _PlanChip(isPremium: isPremium),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onEdit,
                      child: const Padding(
                        padding: EdgeInsets.all(9),
                        child: Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  final bool isPremium;
  const _PlanChip({required this.isPremium});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        gradient: isPremium
            ? const LinearGradient(
                colors: [Color(0xFFFFC107), Color(0xFFFF8F00)],
              )
            : null,
        color: isPremium ? null : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: isPremium
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPremium ? Icons.workspace_premium : Icons.auto_awesome,
            size: 11,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            isPremium ? 'PREMIUM' : 'FREE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Золотой бейдж «PRO» у тайла Premium.
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFC107), Color(0xFFFF8F00)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool isDark;
  final Widget? badge;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.isDark,
    this.subtitle,
    this.titleColor,
    this.onTap,
    this.badge,
    this.trailing,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final textColor =
        widget.titleColor ?? (isDark ? Colors.white : const Color(0xFF1A1A2E));
    final subColor = isDark ? Colors.white38 : Colors.grey.shade500;
    final chevronColor = isDark ? Colors.white24 : Colors.grey.shade400;

    final trailingItems = <Widget>[
      if (widget.badge != null) widget.badge!,
      if (widget.trailing != null)
        widget.trailing!
      else if (widget.onTap != null) ...[
        const SizedBox(width: 6),
        Icon(Icons.chevron_right, color: chevronColor, size: 20),
      ],
    ];

    final tile = ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: widget.iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(widget.icon, color: widget.iconColor, size: 20),
      ),
      title: Text(
        widget.title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: textColor,
        ),
      ),
      subtitle: widget.subtitle != null
          ? Text(
              widget.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: subColor),
            )
          : null,
      trailing: trailingItems.isNotEmpty
          ? Row(mainAxisSize: MainAxisSize.min, children: trailingItems)
          : null,
      onTap: widget.onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    if (widget.onTap == null) return tile;

    // Лёгкое «проседание» при нажатии — тактильный отклик без haptic.
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: tile,
      ),
    );
  }
}

class _ThemedDialog extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget content;
  final List<Widget> actions;
  const _ThemedDialog({
    required this.isDark,
    required this.title,
    required this.content,
    required this.actions,
  });

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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: actions
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: a,
                    ),
                  )
                  .toList(),
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
    required this.controller,
    required this.hint,
    required this.isDark,
    this.obscure = false,
    this.autofocus = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : const Color(0xFFF2F6FC);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE8EDF5);
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5),
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool primary;
  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.isDark,
    this.primary = false,
  });

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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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

// ─── Edit-profile bottom sheet ────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final AuthUser user;
  final String initials;
  final String? resolvedAvatarUrl;
  final bool isDark;
  final AppLocalizations l10n;
  final void Function(AuthUser) onSaved;

  const _EditProfileSheet({
    required this.user,
    required this.initials,
    required this.resolvedAvatarUrl,
    required this.isDark,
    required this.l10n,
    required this.onSaved,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  File? _newAvatarFile;
  bool _loading = false;
  bool _connectingGoogle = false;
  bool _connectingTelegram = false;
  late AuthUser _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _nameCtrl = TextEditingController(text: widget.user.name);
    _emailCtrl = TextEditingController(
        text: _isSyntheticEmail(widget.user.email) ? '' : widget.user.email);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      setState(() => _newAvatarFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      AuthUser updated = widget.user;

      if (_newAvatarFile != null) {
        updated = await AuthService().updateAvatar(_newAvatarFile!.path);
      }

      final newName = _nameCtrl.text.trim();
      final newEmail = _emailCtrl.text.trim();
      final nameChanged = newName.isNotEmpty && newName != updated.name;
      final emailChanged = newEmail.isNotEmpty && newEmail != updated.email;

      if (nameChanged || emailChanged) {
        updated = await AuthService().updateProfile(
          name: nameChanged ? newName : null,
          email: emailChanged ? newEmail : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved(updated);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectGoogle() async {
    setState(() => _connectingGoogle = true);
    try {
      final user = await SocialAuthService().loginWithGoogle(context);
      if (!mounted) return;
      setState(() => _currentUser = user);
      widget.onSaved(user);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _connectingGoogle = false);
    }
  }

  Future<void> _connectTelegram() async {
    setState(() => _connectingTelegram = true);
    try {
      final user = await SocialAuthService().linkWithTelegram(context);
      if (!mounted) return;
      setState(() => _currentUser = user);
      widget.onSaved(user);
      AppNotification.show(
        context,
        message: widget.l10n.profileTelegramLinked,
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppNotification.show(
        context,
        message: friendlyError(e),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _connectingTelegram = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1A2332) : const Color(0xFFF5F9FF);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final handleColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFCDD9EE);
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFD8E4F4);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final isGoogle = _currentUser.hasGoogleLinked ||
        (_currentUser.provider ?? '').toLowerCase().contains('google');
    final isTelegram = _currentUser.hasTelegramLinked ||
        (_currentUser.provider ?? '').toLowerCase().contains('telegram');

    ImageProvider? avatarImg;
    if (_newAvatarFile != null) {
      avatarImg = FileImage(_newAvatarFile!);
    } else if (widget.resolvedAvatarUrl != null) {
      avatarImg = NetworkImage(widget.resolvedAvatarUrl!);
    }

    final screenH = MediaQuery.of(context).size.height;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardH),
      child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenH * 0.88),
      child: Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header — заголовок по центру, без крестика
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Center(
              child: Text(
                widget.l10n.profileEditTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: divColor),

          // Content по высоте содержимого, скроллится при клавиатуре
          Flexible(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  // Avatar picker
                  Center(
                    child: GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.15),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: avatarImg != null
                                  ? Image(
                                      image: avatarImg,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _InitialsFallback(
                                        initials: widget.initials,
                                        isDark: isDark,
                                      ),
                                    )
                                  : _InitialsFallback(
                                      initials: widget.initials,
                                      isDark: isDark,
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2CA5E0),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      widget.l10n.profileChangePhoto,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF2CA5E0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Name
                  _ThemedTextField(
                    controller: _nameCtrl,
                    hint: widget.l10n.fieldName,
                    isDark: isDark,
                    autofocus: false,
                  ),
                  const SizedBox(height: 12),

                  // Email
                  _ThemedTextField(
                    controller: _emailCtrl,
                    hint: widget.l10n.fieldEmail,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 28),

                  // Connected accounts
                  Text(
                    widget.l10n.profileConnectedAccounts.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: subColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _AccountBadge(
                    icon: FontAwesomeIcons.google,
                    label: 'Google',
                    accentColor: const Color(0xFFEA4335),
                    connected: isGoogle,
                    isDark: isDark,
                    onTap: _connectingGoogle ? null : _connectGoogle,
                    loading: _connectingGoogle,
                  ),
                  const SizedBox(height: 10),
                  _AccountBadge(
                    icon: FontAwesomeIcons.telegram,
                    label: 'Telegram',
                    accentColor: const Color(0xFF2AABEE),
                    connected: isTelegram,
                    isDark: isDark,
                    onTap: _connectingTelegram ? null : _connectTelegram,
                    loading: _connectingTelegram,
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2CA5E0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.l10n.actionSave,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
    ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  final String initials;
  final bool isDark;
  const _InitialsFallback({required this.initials, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2CA5E0).withValues(alpha: isDark ? 0.30 : 0.18),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(
              Icons.person_outline_rounded,
              color: const Color(0xFF2CA5E0),
              size: 36,
            )
          : Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF2CA5E0),
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _AccountBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final bool connected;
  final bool isDark;
  final bool loading;
  final VoidCallback? onTap;

  const _AccountBadge({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.connected,
    required this.isDark,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardBg = connected
        ? accentColor.withValues(alpha: isDark ? 0.14 : 0.08)
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.8));
    final borderColor = connected
        ? accentColor.withValues(alpha: 0.38)
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFDDE3ED));
    final iconColor =
        connected ? accentColor : (isDark ? Colors.white30 : const Color(0xFFBBC4D4));
    final textColor = connected
        ? (isDark ? Colors.white : const Color(0xFF1A1A2E))
        : (isDark ? Colors.white38 : const Color(0xFFAAB4C8));
    final subText = connected
        ? (isDark ? Colors.white38 : Colors.grey.shade500)
        : (isDark ? Colors.white24 : const Color(0xFFCDD9EE));

    return GestureDetector(
      onTap: (connected || loading) ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: !connected && onTap != null
                ? accentColor.withValues(alpha: isDark ? 0.22 : 0.28)
                : borderColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: FaIcon(icon, size: 18, color: iconColor),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: !connected && onTap != null
                          ? accentColor.withValues(alpha: 0.85)
                          : textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    connected ? l10n.profileConnected : l10n.profileConnect,
                    style: TextStyle(
                      fontSize: 12,
                      color: connected ? const Color(0xFF26C060) : subText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (loading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: accentColor,
                ),
              )
            else
              Icon(
                connected
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_ios_rounded,
                size: connected ? 22 : 14,
                color: connected
                    ? const Color(0xFF26C060)
                    : (onTap != null
                        ? accentColor.withValues(alpha: 0.55)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.20)
                            : const Color(0xFFCDD9EE))),
              ),
          ],
        ),
      ),
    );
  }
}
