import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../config/server_config.dart';
import '../screens/auth/oauth_webview_screen.dart';
import 'api_service.dart';
import 'auth_service.dart';

class SocialAuthService {
  final _authService = AuthService();

  static const _googleWebClientId =
      '408293307028-59uhh1lio31abr5r3cof7undvqarj6e7.apps.googleusercontent.com';

  static Uri buildGoogleAuthUri([String? redirectUri]) {
    final effectiveRedirectUri =
        redirectUri ?? '${ServerConfig().baseUrl}/auth/google/callback';
    return Uri.https('accounts.google.com', '/o/oauth2/auth', {
      'client_id': _googleWebClientId,
      'redirect_uri': effectiveRedirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'access_type': 'offline',
      'prompt': 'select_account',
    });
  }

  /// Извлекает одноразовый OAuth code из deep link и валидирует ошибки.
  static String extractOAuthCode(Uri resultUri) {
    final params = resultUri.queryParameters;
    final error = params['error'];
    if (error != null && error.isNotEmpty) {
      if (error == 'access_denied') throw 'Вход отменён.';
      throw 'Ошибка авторизации: $error';
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw 'Сервер не вернул код авторизации.';
    }
    return code;
  }

  Future<AuthUser> _exchangeCodeForTokens(String code) async {
    final response = await ApiService()
        .dio
        .post('/auth/oauth/exchange', data: {'code': code});

    final data = response.data as Map<String, dynamic>?;
    if (data == null) throw 'Пустой ответ от сервера.';
    final token = data['token'] as String?;
    if (token == null || token.isEmpty) throw 'Сервер не вернул токен.';
    final refreshToken = data['refreshToken'] as String?;
    await _authService.saveTokens(
      token,
      refreshToken,
      sessionId: data['sessionId'] as String?,
    );

    final userJson = data['user'] as Map<String, dynamic>?;
    if (userJson == null) throw 'Сервер не вернул профиль пользователя.';
    return AuthUser.fromJson(userJson);
  }

  // ── Google ──────────────────────────────────────────────────────────────

  Future<AuthUser> loginWithGoogle(BuildContext context) async {
    final uri = buildGoogleAuthUri();
    final resultUri = await showOAuthBottomSheet(
      context,
      url: uri.toString(),
    );
    if (resultUri == null) throw 'Вход через Google отменён.';
    final code = extractOAuthCode(resultUri);
    return _exchangeCodeForTokens(code);
  }

  // ── Telegram ─────────────────────────────────────────────────────────────

  static String buildTelegramLoginUrl(String baseUrl) =>
      '$baseUrl/auth/telegram/login';

  static String buildTelegramLinkUrl(String baseUrl) =>
      '$baseUrl/auth/telegram/link-page';

  Future<AuthUser> loginWithTelegram(BuildContext context) async {
    final loginUrl = buildTelegramLoginUrl(ServerConfig().baseUrl);
    final resultUri = await showOAuthBottomSheet(
      context,
      url: loginUrl,
    );
    if (resultUri == null) throw 'Авторизация Telegram отменена.';
    final code = extractOAuthCode(resultUri);
    return _exchangeCodeForTokens(code);
  }

  /// Открывает Telegram OAuth для привязки аккаунта к уже авторизованному пользователю.
  /// Возвращает обновлённый [AuthUser] с [hasTelegramLinked] == true.
  Future<AuthUser> linkWithTelegram(BuildContext context) async {
    final linkUrl = buildTelegramLinkUrl(ServerConfig().baseUrl);
    final resultUri = await showOAuthBottomSheet(
      context,
      url: linkUrl,
    );
    if (resultUri == null) throw 'Привязка Telegram отменена.';

    // Deep link: aurascanner://tglink?id=...&hash=...&auth_date=...&...
    if (resultUri.host != 'tglink') {
      throw 'Неожиданный ответ сервера.';
    }
    final params = resultUri.queryParameters;
    final id = params['id'];
    final hash = params['hash'];
    final authDate = params['auth_date'];
    if (id == null || hash == null || authDate == null) {
      throw 'Не получены данные Telegram.';
    }

    return AuthService().linkTelegram(
      id: id,
      hash: hash,
      authDate: authDate,
      firstName: params['first_name'],
      lastName: params['last_name'],
      username: params['username'],
      photoUrl: params['photo_url'],
    );
  }

  // ── Apple ────────────────────────────────────────────────────────────────

  static bool get isAppleSignInSupported => Platform.isIOS || Platform.isMacOS;

  Future<AuthUser> loginWithApple() async {
    if (!isAppleSignInSupported) {
      throw 'Вход через Apple доступен только на iOS и macOS.';
    }

    final available = await SignInWithApple.isAvailable();
    if (!available) {
      throw 'Apple Sign In недоступен на этом устройстве.';
    }

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw 'Вход через Apple отменён.';
      }
      throw 'Ошибка входа через Apple: ${e.message}';
    }

    final identityToken = credential.identityToken;
    if (identityToken == null || identityToken.isEmpty) {
      throw 'Apple не вернул identity token.';
    }

    final givenName = credential.givenName ?? '';
    final familyName = credential.familyName ?? '';
    final fullName =
        [givenName, familyName].where((s) => s.isNotEmpty).join(' ');

    return _authService.loginWithSocial(
      provider: 'apple',
      token: identityToken,
      email: credential.email,
      name: fullName.isNotEmpty ? fullName : null,
      extra: {
        if (credential.authorizationCode.isNotEmpty)
          'authorizationCode': credential.authorizationCode,
        if (credential.userIdentifier != null)
          'userIdentifier': credential.userIdentifier,
      },
    );
  }
}
