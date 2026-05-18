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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          final url = request.url;

          // Direct custom scheme
          if (url.startsWith('aurascanner://')) {
            Navigator.of(context).pop(Uri.parse(url));
            return NavigationDecision.prevent;
          }

          // intent:// URI produced by backend HTML for Android Chrome.
          // Format: intent://HOST?QUERY#Intent;scheme=aurascanner;...;end
          if (url.startsWith('intent://')) {
            final match = RegExp(
              r'intent://([^#]+)#Intent;scheme=aurascanner',
            ).firstMatch(url);
            if (match != null) {
              Navigator.of(context).pop(
                Uri.parse('aurascanner://${match.group(1)}'),
              );
              return NavigationDecision.prevent;
            }
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
