import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

class DeepLinkService with WidgetsBindingObserver {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Completer<Uri>? _pendingCompleter;

  void init() {
    WidgetsBinding.instance.addObserver(this);
    _sub = _appLinks.uriLinkStream.listen(_onUri);
  }

  // When app comes to foreground via deep link, getInitialAppLink may carry the URI
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingCompleter != null) {
      _appLinks.getLatestLink().then((uri) {
        if (uri != null) _onUri(uri);
      });
    }
  }

  void _onUri(Uri uri) {
    if (uri.scheme != 'aurascanner') return;
    final completer = _pendingCompleter;
    if (completer != null && !completer.isCompleted) {
      _pendingCompleter = null;
      completer.complete(uri);
    }
  }

  Future<Uri> waitForLink({Duration timeout = const Duration(minutes: 5)}) {
    _pendingCompleter = Completer<Uri>();
    return _pendingCompleter!.future.timeout(
      timeout,
      onTimeout: () {
        _pendingCompleter = null;
        throw TimeoutException('Deep link timeout', timeout);
      },
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
  }
}
