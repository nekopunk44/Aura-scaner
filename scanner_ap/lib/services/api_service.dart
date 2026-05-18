import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_config.dart';

class _PendingRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;
  _PendingRequest(this.options, this.handler);
}

class ApiService {
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  bool _isRefreshing = false;
  final List<_PendingRequest> _pendingRequests = [];

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: ServerConfig().baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ))
    ..interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isAuthPath = _isAuthEndpoint(error.requestOptions.path);
        final isRetry = error.requestOptions.extra['_retry'] == true;

        if (error.response?.statusCode == 401 && !isAuthPath && !isRetry) {
          await _handleUnauthorized(error, handler);
          return;
        }
        handler.next(error);
      },
    ));

  bool _isAuthEndpoint(String path) =>
      path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/social');

  Future<void> _handleUnauthorized(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    if (_isRefreshing) {
      _pendingRequests.add(_PendingRequest(error.requestOptions, handler));
      return;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        await clearAllTokens();
        handler.next(error);
        return;
      }

      final refreshResponse = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'_retry': true}),
      );

      final newToken = refreshResponse.data['token'] as String;
      final newRefreshToken = refreshResponse.data['refreshToken'] as String;
      await saveToken(newToken);
      await saveRefreshToken(newRefreshToken);

      // Повторяем исходный запрос с новым токеном
      final retryOptions = error.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newToken';
      retryOptions.extra['_retry'] = true;
      final retryResponse = await _dio.fetch(retryOptions);
      handler.resolve(retryResponse);

      // Повторяем все запросы которые ждали в очереди
      for (final pending in _pendingRequests) {
        pending.options.headers['Authorization'] = 'Bearer $newToken';
        pending.options.extra['_retry'] = true;
        try {
          final r = await _dio.fetch(pending.options);
          pending.handler.resolve(r);
        } catch (e) {
          pending.handler.next(error);
        }
      }
      _pendingRequests.clear();
    } catch (_) {
      // Refresh не удался — разлогиниваем
      await clearAllTokens();
      handler.next(error);
      for (final pending in _pendingRequests) {
        pending.handler.next(error);
      }
      _pendingRequests.clear();
    } finally {
      _isRefreshing = false;
    }
  }

  Dio get dio => _dio;

  Future<void> syncBaseUrl() async {
    await ServerConfig().load();
    _dio.options.baseUrl = ServerConfig().baseUrl;
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> clearAllTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}
