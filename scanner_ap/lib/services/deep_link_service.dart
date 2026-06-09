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

  Future<Uri> waitForLink({Duration timeout = const Duration(minutes: 2)}) {
    // Если уже есть незавершённый ожидающий вызов (например, юзер нажал
    // Google, потом сразу VK), отменяем старый чтобы не потерять его навсегда
    // и не дать ему получить чужой результат.
    final prev = _pendingCompleter;
    if (prev != null && !prev.isCompleted) {
      prev.completeError(
        StateError('Авторизация прервана новым запросом входа.'),
      );
    }

    final completer = Completer<Uri>();
    _pendingCompleter = completer;

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        if (identical(_pendingCompleter, completer)) {
          _pendingCompleter = null;
        }
        throw TimeoutException('Deep link timeout', timeout);
      },
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
  }
}
