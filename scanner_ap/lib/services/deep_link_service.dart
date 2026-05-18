import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Completer<Uri>? _pendingCompleter;

  /// Call once at app startup.
  void init() {
    _sub = _appLinks.uriLinkStream.listen(_onUri);
  }

  void _onUri(Uri uri) {
    if (_pendingCompleter != null && !_pendingCompleter!.isCompleted) {
      _pendingCompleter!.complete(uri);
      _pendingCompleter = null;
    }
  }

  /// Returns a Future that completes with the next incoming deep-link URI.
  /// Times out after [timeout] (default 5 min).
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
    _sub?.cancel();
  }
}
