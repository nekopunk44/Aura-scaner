import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_ap/services/social_auth_service.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // Google OAuth
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

  group('Google — parseGoogleDeepLink', () {
    test('возвращает AuthUser при корректных параметрах', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect'
        '?token=JWT123&refreshToken=RT456'
        '&userId=user1&email=test@example.com&name=Test+User',
      );
      final user = SocialAuthService.parseGoogleDeepLink(uri);
      expect(user.id, equals('user1'));
      expect(user.email, equals('test@example.com'));
      expect(user.name, equals('Test User'));
    });

    test('name берётся из email когда поле name отсутствует', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect'
        '?token=JWT&userId=u1&email=hello@mail.com',
      );
      final user = SocialAuthService.parseGoogleDeepLink(uri);
      expect(user.name, equals('hello'));
    });

    test('throws при наличии параметра error', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?error=access_denied',
      );
      expect(
        () => SocialAuthService.parseGoogleDeepLink(uri),
        throwsA(contains('access_denied')),
      );
    });

    test('throws когда token отсутствует', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?userId=u1&email=a@b.com',
      );
      expect(
        () => SocialAuthService.parseGoogleDeepLink(uri),
        throwsA(isA<String>()),
      );
    });

    test('throws когда token пустой', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?token=&userId=u1&email=a@b.com',
      );
      expect(
        () => SocialAuthService.parseGoogleDeepLink(uri),
        throwsA(isA<String>()),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Telegram OAuth
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

  group('Telegram — parseTelegramDeepLink', () {
    test('возвращает все поля при полных параметрах', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect'
        '?id=123456&hash=abc&auth_date=1700000000'
        '&first_name=Ivan&last_name=Petrov&username=ivanp',
      );
      final r = SocialAuthService.parseTelegramDeepLink(uri);
      expect(r.id, equals('123456'));
      expect(r.hash, equals('abc'));
      expect(r.authDate, equals('1700000000'));
      expect(r.name, equals('Ivan Petrov'));
      expect(r.email, equals('tg_123456@telegram.placeholder'));
      expect(r.extra['first_name'], equals('Ivan'));
      expect(r.extra['last_name'], equals('Petrov'));
      expect(r.extra['username'], equals('ivanp'));
    });

    test('name берётся из username когда first/last_name отсутствуют', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect'
        '?id=777&hash=xyz&auth_date=1700000001&username=mybot',
      );
      final r = SocialAuthService.parseTelegramDeepLink(uri);
      expect(r.name, equals('mybot'));
    });

    test('name — fallback на tg_id когда нет имени и username', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?id=999&hash=h&auth_date=1700',
      );
      final r = SocialAuthService.parseTelegramDeepLink(uri);
      expect(r.name, equals('tg_999'));
    });

    test('extra не содержит username когда он равен tg_{id}', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?id=42&hash=h&auth_date=1700',
      );
      final r = SocialAuthService.parseTelegramDeepLink(uri);
      expect(r.extra.containsKey('username'), isFalse);
    });

    test('throws когда id отсутствует', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?hash=h&auth_date=1700',
      );
      expect(
        () => SocialAuthService.parseTelegramDeepLink(uri),
        throwsA(isA<String>()),
      );
    });

    test('throws когда hash отсутствует', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?id=1&auth_date=1700',
      );
      expect(
        () => SocialAuthService.parseTelegramDeepLink(uri),
        throwsA(isA<String>()),
      );
    });

    test('throws когда auth_date отсутствует', () {
      final uri = Uri.parse(
        'aurascanner://oauth2redirect?id=1&hash=h',
      );
      expect(
        () => SocialAuthService.parseTelegramDeepLink(uri),
        throwsA(isA<String>()),
      );
    });
  });
}
