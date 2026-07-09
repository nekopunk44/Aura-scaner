import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/app_notification.dart';

/// Управление офлайн-моделями перевода: какие языки скачаны, сколько это
/// занимает, удаление ненужных и ручная догрузка. Модели качаются
/// автоматически при первом переводе пары — этот экран нужен, чтобы
/// контролировать место на устройстве.
class TranslationModelsScreen extends StatefulWidget {
  const TranslationModelsScreen({super.key});

  @override
  State<TranslationModelsScreen> createState() =>
      _TranslationModelsScreenState();
}

class _TranslationModelsScreenState extends State<TranslationModelsScreen> {
  final OnDeviceTranslatorModelManager _manager =
      OnDeviceTranslatorModelManager();

  /// bcp-код → скачана ли модель.
  final Map<String, bool> _downloaded = {};

  /// Коды, над которыми прямо сейчас идёт операция (скачивание/удаление).
  final Set<String> _busy = {};

  bool _loading = true;

  /// Нативные названия языков ML Kit-перевода (bcp → имя).
  static const Map<String, String> _names = {
    'af': 'Afrikaans',
    'sq': 'Shqip',
    'ar': 'العربية',
    'be': 'Беларуская',
    'bn': 'বাংলা',
    'bg': 'Български',
    'ca': 'Català',
    'zh': '中文',
    'hr': 'Hrvatski',
    'cs': 'Čeština',
    'da': 'Dansk',
    'nl': 'Nederlands',
    'en': 'English',
    'eo': 'Esperanto',
    'et': 'Eesti',
    'fi': 'Suomi',
    'fr': 'Français',
    'gl': 'Galego',
    'ka': 'ქართული',
    'de': 'Deutsch',
    'el': 'Ελληνικά',
    'gu': 'ગુજરાતી',
    'ht': 'Kreyòl ayisyen',
    'he': 'עברית',
    'hi': 'हिन्दी',
    'hu': 'Magyar',
    'is': 'Íslenska',
    'id': 'Indonesia',
    'ga': 'Gaeilge',
    'it': 'Italiano',
    'ja': '日本語',
    'kn': 'ಕನ್ನಡ',
    'ko': '한국어',
    'lv': 'Latviešu',
    'lt': 'Lietuvių',
    'mk': 'Македонски',
    'ms': 'Melayu',
    'mt': 'Malti',
    'mr': 'मराठी',
    'no': 'Norsk',
    'fa': 'فارسی',
    'pl': 'Polski',
    'pt': 'Português',
    'ro': 'Română',
    'ru': 'Русский',
    'sk': 'Slovenčina',
    'sl': 'Slovenščina',
    'es': 'Español',
    'sw': 'Kiswahili',
    'sv': 'Svenska',
    'tl': 'Filipino',
    'ta': 'தமிழ்',
    'te': 'తెలుగు',
    'th': 'ไทย',
    'tr': 'Türkçe',
    'uk': 'Українська',
    'ur': 'اردو',
    'vi': 'Tiếng Việt',
    'cy': 'Cymraeg',
  };

  @override
  void initState() {
    super.initState();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final codes =
        TranslateLanguage.values.map((lang) => lang.bcpCode).toList();
    final statuses = await Future.wait(
      codes.map((code) => _manager.isModelDownloaded(code)),
    );
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < codes.length; i++) {
        _downloaded[codes[i]] = statuses[i];
      }
      _loading = false;
    });
  }

  Future<void> _delete(String code) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy.add(code));
    try {
      await _manager.deleteModel(code);
      if (!mounted) return;
      setState(() => _downloaded[code] = false);
      AppNotification.show(
        context,
        message: l10n.tmDeleted,
        type: NotificationType.success,
      );
    } catch (e) {
      debugPrint('Модели перевода: ошибка удаления $code: $e');
      if (mounted) {
        AppNotification.show(
          context,
          message: l10n.tmError,
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  Future<void> _download(String code) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy.add(code));
    try {
      await _manager
          .downloadModel(code, isWifiRequired: false)
          .timeout(const Duration(seconds: 90));
      if (!mounted) return;
      setState(() => _downloaded[code] = true);
      AppNotification.show(
        context,
        message: l10n.tmDownloadedMsg,
        type: NotificationType.success,
      );
    } catch (e) {
      debugPrint('Модели перевода: ошибка загрузки $code: $e');
      if (mounted) {
        AppNotification.show(
          context,
          message: l10n.tmError,
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  String _nameFor(String code) => _names[code] ?? code.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg =
        isDark ? const Color(0xFF0F1923) : const Color(0xFFE8EFF9);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white38 : Colors.grey.shade500;

    final codes = _downloaded.keys.toList()
      ..sort((a, b) => _nameFor(a).compareTo(_nameFor(b)));
    final downloadedCodes =
        codes.where((c) => _downloaded[c] == true).toList();
    final availableCodes =
        codes.where((c) => _downloaded[c] != true).toList();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          l10n.settingsTranslateModels,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2CA5E0)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Инфо-баннер: как работают модели.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2CA5E0)
                        .withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFF2CA5E0), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.tmInfoBanner,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: textColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                _sectionHeader(
                  '${l10n.tmDownloadedSection} (${downloadedCodes.length})',
                  subColor,
                ),
                if (downloadedCodes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      l10n.tmNothingDownloaded,
                      style: TextStyle(fontSize: 13, color: subColor),
                    ),
                  )
                else
                  _card(
                    cardBg,
                    isDark,
                    [
                      for (final code in downloadedCodes)
                        _languageTile(code, downloaded: true,
                            textColor: textColor, subColor: subColor),
                    ],
                  ),
                const SizedBox(height: 18),

                _sectionHeader(
                  '${l10n.tmAvailableSection} (${availableCodes.length})',
                  subColor,
                ),
                _card(
                  cardBg,
                  isDark,
                  [
                    for (final code in availableCodes)
                      _languageTile(code, downloaded: false,
                          textColor: textColor, subColor: subColor),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _card(Color bg, bool isDark, List<Widget> children) {
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100;
    return Container(
      decoration: BoxDecoration(
        color: bg,
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
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(height: 1, indent: 56, color: dividerColor),
          ],
        ],
      ),
    );
  }

  Widget _languageTile(
    String code, {
    required bool downloaded,
    required Color textColor,
    required Color subColor,
  }) {
    final l10n = AppLocalizations.of(context);
    final busy = _busy.contains(code);
    // Английский — базовый (пивот) язык ML Kit: через него идут все
    // переводы, удалять его нельзя.
    final isBase = code == 'en';

    Widget trailing;
    if (busy) {
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF2CA5E0),
        ),
      );
    } else if (downloaded) {
      trailing = isBase
          ? Icon(Icons.lock_outline, size: 18, color: subColor)
          : IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 22),
              tooltip: l10n.actionDelete,
              onPressed: () => _delete(code),
            );
    } else {
      trailing = IconButton(
        icon: const Icon(Icons.download_outlined,
            color: Color(0xFF2CA5E0), size: 22),
        tooltip: l10n.tmDownloadTooltip,
        onPressed: () => _download(code),
      );
    }

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (downloaded ? const Color(0xFF26C060) : const Color(0xFF2CA5E0))
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          code.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: downloaded
                ? const Color(0xFF26C060)
                : const Color(0xFF2CA5E0),
          ),
        ),
      ),
      title: Text(
        _nameFor(code),
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: textColor,
        ),
      ),
      subtitle: Text(
        isBase && downloaded ? l10n.tmBaseModel : l10n.tmModelSize,
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      trailing: trailing,
    );
  }
}
