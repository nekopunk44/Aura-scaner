import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/auth_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/error_messages.dart';
import '../../l10n/app_localizations.dart';

class SessionManagementScreen extends StatefulWidget {
  const SessionManagementScreen({super.key});

  @override
  State<SessionManagementScreen> createState() => _SessionManagementScreenState();
}

class _SessionManagementScreenState extends State<SessionManagementScreen> {
  final _authService = AuthService();

  bool _isLoading = true;
  bool _isMutating = false;
  List<UserSession> _sessions = const [];

  bool _isRu(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ru';

  String _title(BuildContext context) =>
      _isRu(context) ? 'Активные сессии' : 'Active sessions';

  String _subtitle(BuildContext context) => _isRu(context)
      ? 'Управление вошедшими устройствами'
      : 'Manage signed-in devices';

  String _currentLabel(BuildContext context) =>
      _isRu(context) ? 'Текущее устройство' : 'Current device';

  String _emptyLabel(BuildContext context) => _isRu(context)
      ? 'Других активных сессий не найдено.'
      : 'No other active sessions were found.';

  String _logoutOthersLabel(BuildContext context) => _isRu(context)
      ? 'Выйти на других устройствах'
      : 'Log out other devices';

  String _logoutOthersTitle(BuildContext context) => _isRu(context)
      ? 'Завершить другие сессии?'
      : 'Log out other devices?';

  String _logoutOthersBody(BuildContext context) => _isRu(context)
      ? 'Все остальные устройства должны будут войти заново.'
      : 'Other signed-in devices will need to log in again.';

  String _logoutSessionLabel(BuildContext context) =>
      _isRu(context) ? 'Завершить эту сессию' : 'Log out this device';

  String _startedLabel(BuildContext context) =>
      _isRu(context) ? 'Начата' : 'Started';

  String _lastUsedLabel(BuildContext context) =>
      _isRu(context) ? 'Последняя активность' : 'Last used';

  String _unknownDeviceLabel(BuildContext context) =>
      _isRu(context) ? 'Неизвестное устройство' : 'Unknown device';

  String _sessionEndedLabel(BuildContext context) =>
      _isRu(context) ? 'Сессия завершена' : 'Session ended';

  String _othersEndedLabel(BuildContext context) =>
      _isRu(context) ? 'Остальные сессии завершены' : 'Other sessions ended';

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _authService.getSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppNotification.show(context, message: friendlyError(e), type: NotificationType.error);
    }
  }

  Future<void> _logoutOthers() async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        isDark: isDark,
        icon: Icons.devices_outlined,
        iconColor: const Color(0xFF2CA5E0),
        title: _logoutOthersTitle(context),
        body: _logoutOthersBody(context),
        cancelLabel: l10n.actionCancel,
        confirmLabel: _logoutOthersLabel(context),
        confirmColor: const Color(0xFF2CA5E0),
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isMutating = true);

    try {
      await _authService.logoutOtherSessions();
      await _loadSessions();
      if (!mounted) return;
      AppNotification.show(context, message: _othersEndedLabel(context), type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      AppNotification.show(context, message: friendlyError(e), type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _revokeSession(UserSession session) async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        isDark: isDark,
        icon: Icons.logout_rounded,
        iconColor: Colors.red,
        title: _logoutSessionLabel(context),
        body: _describeDevice(context, session),
        cancelLabel: l10n.actionCancel,
        confirmLabel: _logoutSessionLabel(context),
        confirmColor: Colors.red,
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isMutating = true);

    try {
      await _authService.revokeSession(session.id);
      await _loadSessions();
      if (!mounted) return;
      AppNotification.show(context, message: _sessionEndedLabel(context), type: NotificationType.success);
    } catch (e) {
      if (!mounted) return;
      AppNotification.show(context, message: friendlyError(e), type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  String _describeDevice(BuildContext context, UserSession session) {
    final userAgent = session.userAgent ?? '';
    final lower = userAgent.toLowerCase();

    String platform;
    if (lower.contains('android')) {
      platform = 'Android';
    } else if (lower.contains('iphone') || lower.contains('ipad') || lower.contains('ios')) {
      platform = 'iOS';
    } else if (lower.contains('windows')) {
      platform = 'Windows';
    } else if (lower.contains('mac os') || lower.contains('macintosh')) {
      platform = 'macOS';
    } else if (lower.contains('linux')) {
      platform = 'Linux';
    } else {
      platform = _unknownDeviceLabel(context);
    }

    String client = '';
    if (lower.contains('edg/')) {
      client = 'Edge';
    } else if (lower.contains('chrome/')) {
      client = 'Chrome';
    } else if (lower.contains('safari/') && !lower.contains('chrome/')) {
      client = 'Safari';
    } else if (lower.contains('firefox/')) {
      client = 'Firefox';
    } else if (lower.contains('dart')) {
      client = 'Flutter';
    }

    if (client.isEmpty) return platform;
    return '$platform / $client';
  }

  String _formatDate(BuildContext context, DateTime value) {
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat('dd.MM.yyyy HH:mm', locale).format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sessions = _sessions;
    final current = sessions.where((session) => session.isCurrent).toList();
    final others = sessions.where((session) => !session.isCurrent).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSessions,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _subtitle(context),
                    style: TextStyle(
                      color: isDark ? Colors.white60 : const Color(0xFF6B7A99),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (others.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FilledButton.icon(
                        onPressed: _isMutating ? null : _logoutOthers,
                        icon: const Icon(Icons.devices_outlined),
                        label: Text(_logoutOthersLabel(context)),
                      ),
                    ),
                  ...current.map((session) => _SessionCard(
                        title: _describeDevice(context, session),
                        currentLabel: _currentLabel(context),
                        startedLabel:
                            '${_startedLabel(context)}: ${_formatDate(context, session.startedAt)}',
                        lastUsedLabel:
                            '${_lastUsedLabel(context)}: ${_formatDate(context, session.lastUsedAt)}',
                        ipAddress: session.ipAddress,
                        isCurrent: true,
                      )),
                  ...others.map((session) => _SessionCard(
                        title: _describeDevice(context, session),
                        currentLabel: _currentLabel(context),
                        startedLabel:
                            '${_startedLabel(context)}: ${_formatDate(context, session.startedAt)}',
                        lastUsedLabel:
                            '${_lastUsedLabel(context)}: ${_formatDate(context, session.lastUsedAt)}',
                        ipAddress: session.ipAddress,
                        isCurrent: false,
                        actionLabel: _logoutSessionLabel(context),
                        onAction: _isMutating ? null : () => _revokeSession(session),
                      )),
                  if (others.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 32),
                      child: Center(
                        child: Text(
                          _emptyLabel(context),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                isDark ? Colors.white54 : const Color(0xFF6B7A99),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String cancelLabel;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: subColor, height: 1.45),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : const Color(0xFF6B7A99),
                      side: BorderSide(
                        color: isDark ? Colors.white24 : const Color(0xFFDDE3ED),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(cancelLabel,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.title,
    required this.currentLabel,
    required this.startedLabel,
    required this.lastUsedLabel,
    required this.isCurrent,
    this.ipAddress,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String currentLabel;
  final String startedLabel;
  final String lastUsedLabel;
  final String? ipAddress;
  final bool isCurrent;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      currentLabel,
                      style: const TextStyle(
                        color: Color(0xFF2CA5E0),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(startedLabel, style: TextStyle(color: subColor, fontSize: 13)),
            const SizedBox(height: 4),
            Text(lastUsedLabel, style: TextStyle(color: subColor, fontSize: 13)),
            if (ipAddress != null && ipAddress!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(ipAddress!, style: TextStyle(color: subColor, fontSize: 12)),
            ],
            if (!isCurrent && actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.logout, size: 18),
                  label: Text(actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
