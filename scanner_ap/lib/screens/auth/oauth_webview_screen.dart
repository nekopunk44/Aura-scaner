import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Открывает OAuth-страницу в WebView и перехватывает редирект на aurascanner://.
/// Возвращает URI когда получает callback, или null при отмене.
class OAuthWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const OAuthWebViewScreen({super.key, required this.url, required this.title});

  @override
  State<OAuthWebViewScreen> createState() => _OAuthWebViewScreenState();
}

class _OAuthWebViewScreenState extends State<OAuthWebViewScreen> {
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      // JS channel: backend page calls FlutterAuth.postMessage('aurascanner://...')
      ..addJavaScriptChannel(
        'FlutterAuth',
        onMessageReceived: (msg) => _handleUri(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          final url = request.url;

          if (url.startsWith('aurascanner://')) {
            _handleUri(url);
            return NavigationDecision.prevent;
          }

          if (url.startsWith('intent://')) {
            final match = RegExp(
              r'intent://([^#]+)#Intent;scheme=aurascanner',
            ).firstMatch(url);
            if (match != null) {
              _handleUri('aurascanner://${match.group(1)}');
              return NavigationDecision.prevent;
            }
          }

          // VK Standalone: redirect to oauth.vk.com/blank.html#access_token=...
          if (url.startsWith('https://oauth.vk.com/blank.html')) {
            _handleUri(url);
            return NavigationDecision.prevent;
          }

          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
