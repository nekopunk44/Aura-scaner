import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const String _sessionIdKey = 'session_id';

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
        final sessionId = await getSessionId();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        if (sessionId != null && sessionId.isNotEmpty) {
          options.headers['X-Session-Id'] = sessionId;
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
      final sessionId = await getSessionId();
      if (refreshToken == null) {
        await clearAllTokens();
        handler.next(error);
        return;
      }

      final refreshResponse = await _dio.post(
        '/auth/refresh',
        data: {
          'refreshToken': refreshToken,
          if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
        },
        options: Options(extra: {'_retry': true}),
      );

      final newToken = refreshResponse.data['token'];
      final newRefreshToken = refreshResponse.data['refreshToken'];
      final newSessionId = refreshResponse.data['sessionId'];
      if (newToken is! String || newToken.isEmpty ||
          newRefreshToken is! String || newRefreshToken.isEmpty) {
        throw Exception('Invalid tokens received');
      }
      await saveToken(newToken);
      await saveRefreshToken(newRefreshToken);
      if (newSessionId is String && newSessionId.isNotEmpty) {
        await saveSessionId(newSessionId);
      }

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

  // Токены живут в защищённом хранилище (Keychain / Android Keystore),
  // а не в SharedPreferences: plain-prefs читаются на рутованном
  // устройстве и попадают в облачный бэкап.
  static const _secureStorage = FlutterSecureStorage();

  // Кэш в памяти: interceptor читает токен на каждый запрос, незачем
  // каждый раз ходить в platform channel.
  String? _cachedToken;
  String? _cachedRefreshToken;
  String? _cachedSessionId;
  Future<void>? _migration;

  /// Одноразовый перенос токенов из SharedPreferences (где они лежали
  /// до перехода на secure storage), чтобы не разлогинить пользователей
  /// при обновлении приложения.
  Future<void> _ensureMigrated() => _migration ??= () async {
        final prefs = await SharedPreferences.getInstance();
        final legacyToken = prefs.getString(_tokenKey);
        if (legacyToken != null) {
          await _secureStorage.write(key: _tokenKey, value: legacyToken);
          await prefs.remove(_tokenKey);
        }
        final legacyRefresh = prefs.getString(_refreshTokenKey);
        if (legacyRefresh != null) {
          await _secureStorage.write(key: _refreshTokenKey, value: legacyRefresh);
          await prefs.remove(_refreshTokenKey);
        }
      }();

  Future<void> saveToken(String token) async {
    _cachedToken = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> saveRefreshToken(String token) async {
    _cachedRefreshToken = token;
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  Future<void> saveSessionId(String sessionId) async {
    _cachedSessionId = sessionId;
    await _secureStorage.write(key: _sessionIdKey, value: sessionId);
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    await _ensureMigrated();
    return _cachedToken = await _secureStorage.read(key: _tokenKey);
  }

  Future<String?> getRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;
    await _ensureMigrated();
    return _cachedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);
  }

  Future<String?> getSessionId() async {
    if (_cachedSessionId != null) return _cachedSessionId;
    await _ensureMigrated();
    return _cachedSessionId = await _secureStorage.read(key: _sessionIdKey);
  }

  Future<void> clearToken() async {
    _cachedToken = null;
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<void> clearAllTokens() async {
    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedSessionId = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _sessionIdKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Проверяет, действительна ли сессия на сервере (вызывается на splash
  /// перед входом). В отличие от [isLoggedIn] не довольствуется наличием
  /// токена, а делает реальный запрос — interceptor при этом сам попытается
  /// освежить протухший access-токен.
  ///
  /// Возвращает:
  /// - `false` — токена нет, либо сервер отверг (401) и refresh не помог
  ///   (токены к этому моменту уже очищены interceptor'ом) → нужен повторный
  ///   вход;
  /// - `true` — сервер принял запрос ИЛИ проверить не удалось из-за сети
  ///   (таймаут/нет соединения). Оффлайн-пользователя НЕ разлогиниваем —
  ///   валидность перепроверится при следующем онлайн-запросе.
  Future<bool> validateSession() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    try {
      await _dio.get('/auth/profile');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return false;
      // Сеть недоступна / таймаут / 5xx — не разлогиниваем оптимистично.
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Сбрасывает in-memory кэш токенов и флаг миграции. Только для тестов:
  /// [ApiService] — синглтон, и без сброса состояние течёт между кейсами.
  @visibleForTesting
  void resetForTesting() {
    _cachedToken = null;
    _cachedRefreshToken = null;
    _cachedSessionId = null;
    _migration = null;
  }
}
