import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_ap/services/social_auth_service.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // Google OAuth — построение URL для авторизации
  // ══════════════════════════════════════════════════════════════════════

  group('Google — buildGoogleAuthUri', () {
    test('содержит правильный client_id', () {
      final uri = SocialAuthService.buildGoogleAuthUri();
      expect(
        uri.queryParameters['client_id'],
        equals('408293307028-59uhh1lio31abr5r3cof7undvqarj6e7.apps.googleusercontent.com'),
      );
    });

    test('содержит зарегистрированный redirect_uri', () {
      final uri = SocialAuthService.buildGoogleAuthUri();
      expect(
        uri.queryParameters['redirect_uri'],
        equals('https://aura-scaner-production.up.railway.app/api/auth/google/callback'),
      );
    });

    test('response_type=code', () {
      final uri = SocialAuthService.buildGoogleAuthUri();
      expect(uri.queryParameters['response_type'], equals('code'));
    });

    test('scope включает openid, email, profile', () {
      final uri = SocialAuthService.buildGoogleAuthUri();
      final scope = uri.queryParameters['scope'] ?? '';
      expect(scope, contains('openid'));
      expect(scope, contains('email'));
      expect(scope, contains('profile'));
    });

    test('хост — accounts.google.com', () {
      final uri = SocialAuthService.buildGoogleAuthUri();
      expect(uri.host, equals('accounts.google.com'));
    });

    test('принимает кастомный redirectUri', () {
      final uri = SocialAuthService.buildGoogleAuthUri('https://example.com/cb');
      expect(uri.queryParameters['redirect_uri'], equals('https://example.com/cb'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Telegram OAuth — построение URL для входа
  // ══════════════════════════════════════════════════════════════════════

  group('Telegram — buildTelegramLoginUrl', () {
    test('формирует корректный URL из baseUrl', () {
      const base = 'https://aura-scaner-production.up.railway.app/api';
      final url = SocialAuthService.buildTelegramLoginUrl(base);
      expect(url, equals('$base/auth/telegram/login'));
    });

    test('работает с localhost URL', () {
      const base = 'http://10.0.2.2:3000/api';
      final url = SocialAuthService.buildTelegramLoginUrl(base);
      expect(url, equals('$base/auth/telegram/login'));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // One-time code flow — извлечение и валидация ?code= из deep link
  // Заменили старые parseGoogleDeepLink / parseTelegramDeepLink после
  // фикса утечки токенов через URL (см. Доработка.md, #4).
  // ══════════════════════════════════════════════════════════════════════

  group('extractOAuthCode', () {
    test('возвращает code когда он присутствует', () {
      final uri = Uri.parse('aurascanner://oauth2redirect?code=abc123');
      expect(SocialAuthService.extractOAuthCode(uri), equals('abc123'));
    });

    test('бросает "Вход отменён" при error=access_denied', () {
      final uri = Uri.parse('aurascanner://oauth2redirect?error=access_denied');
      expect(
        () => SocialAuthService.extractOAuthCode(uri),
        throwsA(contains('отменён')),
      );
    });

    test('бросает общую ошибку при произвольном error=…', () {
      final uri = Uri.parse('aurascanner://oauth2redirect?error=server_error');
      expect(
        () => SocialAuthService.extractOAuthCode(uri),
        throwsA(contains('server_error')),
      );
    });

    test('бросает когда code отсутствует', () {
      final uri = Uri.parse('aurascanner://oauth2redirect');
      expect(
        () => SocialAuthService.extractOAuthCode(uri),
        throwsA(isA<String>()),
      );
    });

    test('бросает когда code пустой', () {
      final uri = Uri.parse('aurascanner://oauth2redirect?code=');
      expect(
        () => SocialAuthService.extractOAuthCode(uri),
        throwsA(isA<String>()),
      );
    });

    test('не считает старые токен-параметры за code (защита от регрессии)', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?token=JWT&userId=u1&email=a@b.com',
      );
      expect(
        () => SocialAuthService.extractOAuthCode(uri),
        throwsA(isA<String>()),
      );
    });
  });
}
