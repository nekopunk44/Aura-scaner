import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ─── Bottom-sheet OAuth WebView ──────────────────────────────────────────────

/// Shows an OAuth WebView as a bottom sheet. Returns the intercepted
/// [Uri] on success, or null if the user dismissed.
Future<Uri?> showOAuthBottomSheet(
  BuildContext context, {
  required String url,
  required String title,
  required Widget providerIcon,
}) {
  return showModalBottomSheet<Uri>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: true,
    builder: (_) => _OAuthBottomSheet(
      url: url,
      title: title,
      providerIcon: providerIcon,
    ),
  );
}

class _OAuthBottomSheet extends StatefulWidget {
  final String url;
  final String title;
  final Widget providerIcon;

  const _OAuthBottomSheet({
    required this.url,
    required this.title,
    required this.providerIcon,
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

  @override
  void initState() {
    super.initState();
    _controller = _buildController(widget.url, _handleUri);
    _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A2332) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final handleColor =
        isDark ? Colors.white.withValues(alpha: 0.18) : const Color(0xFFDDE3ED);
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEEF2F8);
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.90,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Handle ──────────────────────────────────────────────────────
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

          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
            child: Row(
              children: [
                widget.providerIcon,
                const SizedBox(width: 10),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color:
                        isDark ? Colors.white54 : const Color(0xFF8A94A6),
                  ),
                  onPressed: () => Navigator.of(context).pop(null),
                ),
              ],
            ),
          ),

          // ── Thin divider + progress ──────────────────────────────────────
          Divider(height: 1, color: dividerColor),
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

WebViewController _buildController(String url, void Function(String) onUri) {
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
