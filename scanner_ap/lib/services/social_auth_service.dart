// Сервис социальной OAuth-авторизации (Google, VK, Telegram, Instagram).
//
// Использует flutter_web_auth_2 для открытия OAuth-страницы в системном
// браузере и перехвата callback через deep link схему.
// ═══════════════════════════════════════════════════════════════════
// НАСТРОЙКА ПЕРЕД ИСПОЛЬЗОВАНИЕМ
// ═══════════════════════════════════════════════════════════════════
//
// Google
//   1. Зайдите в https://console.cloud.google.com
//   2. Создайте проект → API и сервисы → Учётные данные
//   3. Создайте «Идентификатор клиента OAuth 2.0» типа «Веб-приложение»
//   4. В «Разрешённые URI перенаправления» добавьте:
//        com.example.scanner_ap:/oauth2redirect
//   5. Скопируйте Client ID → замените _googleClientId ниже
//
// VK
//   1. Зайдите в https://vk.com/editapp?act=create
//   2. Создайте «Standalone-приложение»
//   3. В настройках приложения скопируйте ID → замените _vkClientId ниже
//   4. В поле «Redirect URI» укажите: com.example.scanner_ap:/oauth2redirect
//
// Telegram
//   Telegram Bot API не поддерживает OAuth для мобильных приложений напрямую.
//   Нужен Telegram Login Widget (только для веба) или bot_token + авторизация
//   через официальное Telegram приложение. Используйте пакет telegram_web_app
//   или реализуйте кастомный flow через Telegram Login.
//   Для активации: замените _telegramBotUsername → настройте backend.
//
// Instagram
//   1. Зайдите в https://developers.facebook.com → Мои приложения
//   2. Создайте приложение типа «Потребитель»
//   3. Добавьте продукт «Instagram Basic Display»
//   4. В OAuth redirect URI укажите: com.example.scanner_ap:/oauth2redirect
//   5. Скопируйте App ID → замените _instagramClientId ниже
//
// Android: в AndroidManifest.xml уже добавлен intent-filter для схемы.
// iOS: добавьте в Info.plist CFBundleURLSchemes → com.example.scanner_ap

import 'dart:async';
import 'dart:io';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../config/server_config.dart';
import 'auth_service.dart';

class SocialAuthService {
  // ── Замените эти константы на реальные значения из консолей разработчика ──

  // Google Client ID зависит от платформы.
  // Android: использует обратную схему от Client ID как redirect URI.
  // iOS: свой Client ID с тем же механизмом обратной схемы.
  static const _googleClientIdAndroid =
      '408293307028-jg4ii6ad6utd27kf723iq2052jjkapk8.apps.googleusercontent.com';
  static const _googleClientIdIos =
      '408293307028-1b19tnjl4dvrocfcv62l8360u7lf0haq.apps.googleusercontent.com';

  static const _googleCallbackSchemeAndroid =
      'com.googleusercontent.apps.408293307028-jg4ii6ad6utd27kf723iq2052jjkapk8';
  static const _googleCallbackSchemeIos =
      'com.googleusercontent.apps.408293307028-1b19tnjl4dvrocfcv62l8360u7lf0haq';

  /// VK Application ID (Standalone-приложение).
  /// Получить: https://vk.com/editapp → настройки приложения → ID приложения
  static const _vkClientId = 'YOUR_VK_CLIENT_ID';

  /// Instagram App ID (Basic Display API).
  /// Получить: https://developers.facebook.com → Instagram Basic Display → App ID
  static const _instagramClientId = 'YOUR_INSTAGRAM_APP_ID';

  // ── Схема deep link для VK, Telegram, Instagram ──────────────────────────
  static const _callbackScheme = 'com.example.scanner_ap';
  static const _redirectUri = '$_callbackScheme:/oauth2redirect';

  final _authService = AuthService();

  // ════════════════════════════════════════════════════════════════════════════
  // Google
  // ════════════════════════════════════════════════════════════════════════════

  /// Открывает Google OAuth в системном браузере, получает access_token,
  /// верифицирует его на backend и возвращает [AuthUser].
  ///
  /// Google возвращает access_token (не id_token) при implicit flow.
  /// Backend ожидает id_token для /auth/social?provider=google, поэтому
  /// мы запрашиваем id_token через response_type=token+id_token.
  Future<AuthUser> loginWithGoogle() async {
    final clientId = Platform.isIOS ? _googleClientIdIos : _googleClientIdAndroid;
    final callbackScheme = Platform.isIOS
        ? _googleCallbackSchemeIos
        : _googleCallbackSchemeAndroid;
    final redirectUri = '$callbackScheme:/oauth2redirect';

    final uri = Uri.https('accounts.google.com', '/o/oauth2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'token id_token',
      'scope': 'openid email profile',
      'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: uri.toString(),
      callbackUrlScheme: callbackScheme,
    );

    // Google возвращает токены во fragment (#id_token=...&access_token=...)
    final fragment = Uri.parse(resultUrl).fragment;
    final params = Uri.splitQueryString(fragment);

    final idToken = params['id_token'];
    if (idToken == null || idToken.isEmpty) {
      throw 'Google не вернул id_token. Проверьте настройки OAuth-приложения.';
    }

    // Отправляем id_token на backend для верификации и получения JWT
    return _authService.loginWithSocial(
      provider: 'google',
      token: idToken,
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // VK
  // ════════════════════════════════════════════════════════════════════════════

  /// Открывает VK OAuth, получает access_token + email, передаёт на backend.
  ///
  /// VK возвращает email прямо в redirect-параметрах при наличии scope=email.
  Future<AuthUser> loginWithVk() async {
    final uri = Uri.https('oauth.vk.com', '/authorize', {
      'client_id': _vkClientId,
      'redirect_uri': _redirectUri,
      'scope': 'email',
      'response_type': 'token',
      'v': '5.131',
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: uri.toString(),
      callbackUrlScheme: _callbackScheme,
    );

    // VK возвращает параметры во fragment: #access_token=...&email=...
    final fragment = Uri.parse(resultUrl).fragment;
    final params = Uri.splitQueryString(fragment);

    final accessToken = params['access_token'];
    if (accessToken == null || accessToken.isEmpty) {
      throw 'VK не вернул access_token. Проверьте настройки приложения VK.';
    }

    // VK может вернуть email в redirect URI при наличии разрешения
    final email = params['email'];
    final userId = params['user_id'];

    // Если email нет в redirect — используем user_id как fallback-идентификатор
    final resolvedEmail = (email != null && email.isNotEmpty)
        ? email
        : 'vk_${userId ?? accessToken.substring(0, 8)}@vk.placeholder';

    return _authService.loginWithSocial(
      provider: 'vk',
      token: accessToken,
      email: resolvedEmail,
      name: params['first_name'],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Telegram
  // ════════════════════════════════════════════════════════════════════════════

  /// Открывает Telegram Login Widget через web-view.
  ///
  /// Telegram не поддерживает стандартный OAuth implicit flow для мобильных.
  /// Используется Telegram Login Widget (HTML-страница), которая вызывает
  /// JavaScript callback. Требует backend-страницу для обработки callback.
  ///
  /// ВАЖНО: Для полноценной работы замените _telegramBotUsername и создайте
  /// на своём backend HTML-страницу с Telegram Login Widget, которая после
  /// авторизации редиректит на com.example.scanner_ap:/oauth2redirect?...
  ///
  /// Документация: https://core.telegram.org/widgets/login
  Future<AuthUser> loginWithTelegram() async {
    // Backend serves an HTML page with Telegram Login Widget at /auth/telegram/login.
    // After user approves, Telegram redirects to /auth/telegram/callback which
    // verifies the hash and redirects back to the app via deep link.
    // Strip /api suffix from base URL to get the server root, then append
    // the Telegram login route (which is mounted at /api/auth/telegram/login).
    final telegramLoginPageUrl =
        '${ServerConfig().baseUrl}/auth/telegram/login';

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: telegramLoginPageUrl,
      callbackUrlScheme: _callbackScheme,
    );

    final params = Uri.parse(resultUrl).queryParameters;
    final telegramId = params['id'];
    final hash = params['hash'];
    final authDate = params['auth_date'];

    if (telegramId == null || hash == null || authDate == null) {
      throw 'Telegram не вернул данные авторизации.';
    }

    final username = params['username'] ?? 'tg_$telegramId';
    final firstName = params['first_name'] ?? '';
    final lastName = params['last_name'] ?? '';
    final name = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

    return _authService.loginWithSocial(
      provider: 'telegram',
      token: hash,
      email: 'tg_$telegramId@telegram.placeholder',
      name: name.isNotEmpty ? name : username,
      extra: {
        'id': telegramId,
        'hash': hash,
        'auth_date': authDate,
        if (firstName.isNotEmpty) 'first_name': firstName,
        if (lastName.isNotEmpty) 'last_name': lastName,
        if (username != 'tg_$telegramId') 'username': username,
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Instagram (Meta Basic Display API)
  // ════════════════════════════════════════════════════════════════════════════

  /// Открывает Instagram OAuth через Basic Display API.
  ///
  /// Instagram Basic Display API не возвращает email — используется user_id.
  /// Для получения email нужен Instagram Graph API с разрешением instagram_manage_insights,
  /// что требует верификации бизнес-аккаунта Meta.
  Future<AuthUser> loginWithInstagram() async {
    final uri = Uri.https('api.instagram.com', '/oauth/authorize', {
      'client_id': _instagramClientId,
      'redirect_uri': _redirectUri,
      'scope': 'user_profile,user_media',
      'response_type': 'code',
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: uri.toString(),
      callbackUrlScheme: _callbackScheme,
    );

    final queryParams = Uri.parse(resultUrl).queryParameters;
    final code = queryParams['code'];

    if (code == null || code.isEmpty) {
      throw 'Instagram не вернул код авторизации.';
    }

    // Instagram Basic Display API использует code flow (не implicit).
    // code нужно обменять на access_token через backend (server-side).
    // Backend должен реализовать POST /auth/instagram/exchange:
    //   Instagram API endpoint: https://api.instagram.com/oauth/access_token
    //   После получения access_token — запросить /me?fields=id,username
    //
    // Передаём code на backend, который сам обменяет его на токен.
    return _authService.loginWithSocial(
      provider: 'instagram',
      token: code,
      // email Instagram не предоставляет — backend использует user_id как идентификатор
    );
  }
}
