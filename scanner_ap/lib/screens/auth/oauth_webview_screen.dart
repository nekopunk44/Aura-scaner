import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../config/theme_config.dart';

// ─── Bottom-sheet OAuth WebView ──────────────────────────────────────────────

/// Shows an OAuth WebView as a bottom sheet. Returns the intercepted
/// [Uri] on success, or null if the user dismissed.
Future<Uri?> showOAuthBottomSheet(
  BuildContext context, {
  required String url,
}) {
  // ThemeNotifier.isDark is the source of truth — avoids reading the system
  // theme from the modal's context, which can be inverted vs the app theme.
  final isDark = ThemeNotifier().isDark;

  return showModalBottomSheet<Uri>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    builder: (_) => _OAuthBottomSheet(
      url: url,
      isDark: isDark,
    ),
  );
}

class _OAuthBottomSheet extends StatefulWidget {
  final String url;
  final bool isDark;

  const _OAuthBottomSheet({
    required this.url,
    required this.isDark,
  });

  @override
  State<_OAuthBottomSheet> createState() => _OAuthBottomSheetState();
}

class _OAuthBottomSheetState extends State<_OAuthBottomSheet> {
  late WebViewController _controller;
  bool _loading = true;

  void _handleUri(String raw) {
    if (!mounted) return;
    try {
      Navigator.of(context).pop(Uri.parse(raw));
    } catch (_) {}
  }

  /// Тёмная тема для OAuth-страниц (Telegram/Google не поддерживают
  /// prefers-color-scheme внутри WebView и всегда рендерятся белыми).
  /// Инвертируем светлые страницы CSS-фильтром (как Dark Reader), картинки
  /// и видео инвертируем обратно, чтобы логотипы/аватарки остались нормальными.
  /// Собственные страницы бэкенда (успех входа) уже тёмные — проверка яркости
  /// фона пропускает их без инверсии.
  static const String _darkModeJs = '''
(function () {
  if (document.getElementById('__auraDark')) return;
  var el = document.body || document.documentElement;
  var bg = getComputedStyle(el).backgroundColor;
  var m = bg ? bg.match(/[\\d.]+/g) : null;
  var light = true;
  if (m && m.length >= 3) {
    var a = m.length > 3 ? parseFloat(m[3]) : 1;
    if (a > 0.01) {
      light = (0.299 * m[0] + 0.587 * m[1] + 0.114 * m[2]) > 140;
    }
  }
  if (!light) return; // страница уже тёмная — не трогаем
  var s = document.createElement('style');
  s.id = '__auraDark';
  s.textContent =
    'html{filter:invert(0.92) hue-rotate(180deg)!important;' +
    'background:#fff!important}' +
    'img,video,picture,canvas,iframe' +
    '{filter:invert(1) hue-rotate(180deg)!important}';
  (document.head || document.documentElement).appendChild(s);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = _buildController(_handleUri);
    // Фон под страницей: в тёмной теме убирает белую вспышку при загрузке.
    // 0xFF141414 = цвет белой страницы после invert(0.92) — совпадает с
    // фоном инвертированных OAuth-страниц.
    _controller.setBackgroundColor(
      widget.isDark ? const Color(0xFF141414) : const Color(0xFFF5F9FF),
    );
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onProgress: (progress) {
          // Инъекция как можно раньше (до полной загрузки), чтобы страница
          // не мигала белым, пока грузятся ресурсы.
          if (widget.isDark && progress >= 60) {
            _controller.runJavaScript(_darkModeJs);
          }
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          if (widget.isDark) {
            _controller.runJavaScript(_darkModeJs);
          } else {
            _controller.runJavaScript(
              "document.documentElement.style.colorScheme = 'light';",
            );
          }
        },
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('aurascanner://')) {
            _handleUri(url);
            return NavigationDecision.prevent;
          }
          if (url.startsWith('intent://')) {
            final match =
                RegExp(r'intent://([^#]+)#Intent;scheme=aurascanner')
                    .firstMatch(url);
            if (match != null) {
              _handleUri('aurascanner://${match.group(1)}');
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
      ),
    );
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    // Тёмный фон шита = цвет инвертированной OAuth-страницы (см. _darkModeJs),
    // чтобы «шапка» с ручкой не отличалась по цвету от содержимого WebView.
    final bg = isDark ? const Color(0xFF141414) : const Color(0xFFF5F9FF);
    final handleColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFCDD9EE);
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.90,
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
        children: [
          // ── Handle ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Loading bar ──────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _loading ? 3 : 0,
            child: _loading
                ? const LinearProgressIndicator(
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF2CA5E0)),
                  )
                : const SizedBox.shrink(),
          ),

          // ── WebView ──────────────────────────────────────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              child: WebViewWidget(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared WebViewController factory ───────────────────────────────────────

WebViewController _buildController(void Function(String) onUri) {
  return WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    )
    ..addJavaScriptChannel(
      'FlutterAuth',
      onMessageReceived: (msg) => onUri(msg.message),
    );
}
