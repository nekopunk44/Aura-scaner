import 'package:dio/dio.dart';

import '../utils/error_messages.dart';
import 'api_service.dart';

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String? provider;
  final String? avatarUrl;
  final bool hasGoogleLinked;
  final bool hasTelegramLinked;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    this.provider,
    this.avatarUrl,
    this.hasGoogleLinked = false,
    this.hasTelegramLinked = false,
  });

  static String? _readString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) return value.toString();
    }
    return null;
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: _readString(json, const ['id', '_id', 'userId']) ?? '',
    email: _readString(json, const ['email']) ?? '',
    name: _readString(json, const ['name', 'displayName', 'username']) ?? '',
    provider: _readString(json, const [
      'provider',
      'authProvider',
      'socialProvider',
    ]),
    avatarUrl: _readString(json, const [
      'avatarUrl',
      'avatar_url',
      'photoUrl',
      'photo_url',
      'picture',
      'image',
      'photo',
    ]),
    hasGoogleLinked: json['hasGoogleLinked'] as bool? ?? false,
    hasTelegramLinked: json['hasTelegramLinked'] as bool? ?? false,
  );
}

class UserSession {
  final String id;
  final DateTime startedAt;
  final DateTime lastUsedAt;
  final String? userAgent;
  final String? ipAddress;
  final bool isCurrent;

  const UserSession({
    required this.id,
    required this.startedAt,
    required this.lastUsedAt,
    required this.isCurrent,
    this.userAgent,
    this.ipAddress,
  });

  static String? _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static DateTime? _readDate(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  factory UserSession.fromJson(Map<String, dynamic> json) {
    final startedAt = _readDate(json, 'startedAt') ?? DateTime.now();
    return UserSession(
      id:
          _readString(json, 'id') ??
          'legacy-session-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      lastUsedAt: _readDate(json, 'lastUsedAt') ?? startedAt,
      userAgent: _readString(json, 'userAgent'),
      ipAddress: _readString(json, 'ipAddress'),
      isCurrent: json['isCurrent'] as bool? ?? false,
    );
  }
}

class AuthService {
  final _api = ApiService();

  Future<AuthUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _api.dio.post(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      await _saveTokens(response.data as Map<String, dynamic>);
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
      final response = await _api.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      await _saveTokens(response.data as Map<String, dynamic>);
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
      final response = await _api.dio.post(
        '/auth/social',
        data: {
          'provider': provider,
          'token': token,
          if (email != null) 'email': email,
          if (name != null) 'name': name,
          if (extra != null) ...extra,
        },
      );
      await _saveTokens(response.data as Map<String, dynamic>);
      return AuthUser.fromJson(response.data['user'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> logout() async {
    try {
      await _api.dio.post('/auth/logout');
    } catch (_) {
      // Local tokens still must be cleared even if the network request fails.
    } finally {
      await _api.clearAllTokens();
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.dio.post(
        '/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<List<UserSession>> getSessions() async {
    try {
      final response = await _api.dio.get('/auth/sessions');
      final raw = response.data['sessions'] as List<dynamic>? ?? const [];
      return raw
          .map((item) => UserSession.fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<int> logoutOtherSessions() async {
    try {
      final response = await _api.dio.post('/auth/logout-others');
      return response.data['count'] as int? ?? 0;
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> revokeSession(String sessionId) async {
    try {
      await _api.dio.delete('/auth/sessions/$sessionId');
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<AuthUser?> getProfile() async {
    try {
      final response = await _api.dio.get('/auth/profile');
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<AuthUser> updateProfile({String? name, String? email}) async {
    try {
      final response = await _api.dio.patch(
        '/auth/profile',
        data: {
          if (name != null) 'name': name,
          if (email != null) 'email': email,
        },
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<AuthUser> linkTelegram({
    required String id,
    required String hash,
    required String authDate,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
  }) async {
    try {
      final response = await _api.dio.post(
        '/auth/link/telegram',
        data: {
          'id': id,
          'hash': hash,
          'auth_date': authDate,
          if (firstName != null) 'first_name': firstName,
          if (lastName != null) 'last_name': lastName,
          if (username != null) 'username': username,
          if (photoUrl != null) 'photo_url': photoUrl,
        },
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<AuthUser> updateAvatar(String imagePath) async {
    try {
      final formData = FormData.fromMap({
        'avatar': await MultipartFile.fromFile(
          imagePath,
          filename: 'avatar.jpg',
        ),
      });
      final response = await _api.dio.patch(
        '/auth/profile/avatar',
        data: formData,
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _parseError(e);
    }
  }

  Future<void> saveTokens(
    String token,
    String? refreshToken, {
    String? sessionId,
  }) async {
    await _api.saveToken(token);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _api.saveRefreshToken(refreshToken);
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      await _api.saveSessionId(sessionId);
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await saveTokens(
      data['token'] as String,
      data['refreshToken'] as String?,
      sessionId: data['sessionId'] as String?,
    );
  }

  String _parseError(DioException e) => friendlyError(e);
}
