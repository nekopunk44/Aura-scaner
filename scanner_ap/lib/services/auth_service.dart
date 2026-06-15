import 'package:dio/dio.dart';
import 'api_service.dart';
import '../utils/error_messages.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;

  const AuthUser({required this.id, required this.email, required this.name});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String,
      );
}

class AuthService {
  final _api = ApiService();

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post('/auth/register', data: {
        'name': name,
        'email': email,
        'password': password,
      });
      await _saveTokens(response.data);
      return AuthUser.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<AuthUser> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      await _saveTokens(response.data);
      return AuthUser.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<AuthUser> loginWithSocial({
    required String provider,
    required String token,
    String? name,
    String? email,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final response = await _api.dio.post('/auth/social', data: {
        'provider': provider,
        'token': token,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
        if (extra != null) ...extra,
      });
      await _saveTokens(response.data);
      return AuthUser.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> logout() async {
    try {
      // Уведомляем сервер — токен попадает в blacklist
      await _api.dio.post('/auth/logout');
    } catch (_) {
      // Игнорируем ошибку сети: всё равно чистим локальные токены
    } finally {
      await _api.clearAllTokens();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.dio.post('/auth/change-password', data: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  /// Профиль текущего пользователя (GET /auth/profile).
  /// null — если не залогинен или сервер недоступен: вызывающий экран
  /// показывает фолбэк без персональных данных.
  Future<AuthUser?> getProfile() async {
    try {
      final response = await _api.dio.get('/auth/profile');
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Обновляет имя/email (PATCH /auth/profile). Передавайте только то, что
  /// изменилось. Возвращает обновлённый профиль.
  Future<AuthUser> updateProfile({String? name, String? email}) async {
    try {
      final response = await _api.dio.patch('/auth/profile', data: {
        if (name != null) 'name': name,
        if (email != null) 'email': email,
      });
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> saveTokens(String token, String? refreshToken) async {
    await _api.saveToken(token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _api.saveRefreshToken(refreshToken);
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await saveTokens(
      data['token'] as String,
      data['refreshToken'] as String?,
    );
  }

  String _parseError(DioException e) => friendlyError(e);
}
