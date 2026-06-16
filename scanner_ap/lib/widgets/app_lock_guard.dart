import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/auth/login_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';

class AppLockGuard extends StatefulWidget {
  const AppLockGuard({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AppLockGuard> createState() => _AppLockGuardState();
}

class _AppLockGuardState extends State<AppLockGuard>
    with WidgetsBindingObserver {
  bool _hasSeenFirstResume = false;
  bool _isLocked = false;
  bool _isAuthenticating = false;
  bool _shouldUnlockOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAuthenticating) return;

    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_prepareLock());
        break;
      case AppLifecycleState.resumed:
        if (!_hasSeenFirstResume) {
          _hasSeenFirstResume = true;
          return;
        }
        if (_shouldUnlockOnResume && _isLocked) {
          unawaited(_unlock());
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<bool> _needsProtection() async {
    final biometric = BiometricService();
    if (!await biometric.isEnabled()) return false;
    if (!await biometric.isAvailable()) return false;
    return ApiService().isLoggedIn();
  }

  Future<void> _prepareLock() async {
    if (!await _needsProtection() || !mounted) return;
    setState(() {
      _shouldUnlockOnResume = true;
      _isLocked = true;
    });
  }

  Future<void> _unlock() async {
    if (_isAuthenticating || !_shouldUnlockOnResume) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _isAuthenticating = true);
    final unlocked = await BiometricService().authenticate(l10n.biometricReason);
    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
      if (unlocked) {
        _shouldUnlockOnResume = false;
        _isLocked = false;
      }
    });
  }

  Future<void> _logout() async {
    await AuthService().logout();
    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
      _isLocked = false;
      _shouldUnlockOnResume = false;
    });

    widget.navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLocked) return widget.child;

    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardColor = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtitleColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        const Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Color(0xA6000000),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: background,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 24,
                          color: Colors.black.withValues(alpha: 0.12),
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2CA5E0).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              size: 32,
                              color: Color(0xFF2CA5E0),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            l10n.secBiometricTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.biometricReason,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_isAuthenticating) ...[
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              l10n.appName,
                              style: TextStyle(
                                color: subtitleColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _unlock,
                                icon: const Icon(Icons.fingerprint),
                                label: Text(l10n.actionRetry),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _logout,
                                child: Text(l10n.actionLogout),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
