import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scanner_ap/services/api_service.dart';

/// In-memory эмуляция flutter_secure_storage через мок его MethodChannel —
/// в unit-тестах нет нативного Keychain/Keystore.
class _FakeSecureStorage {
  final Map<String, String> store = {};
  static const _channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'deleteAll':
          store.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'containsKey':
          return store.containsKey(args['key'] as String);
      }
      return null;
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSecureStorage secure;
  final api = ApiService();

  setUp(() {
    secure = _FakeSecureStorage()..install();
    SharedPreferences.setMockInitialValues({});
    api.resetForTesting();
  });

  tearDown(() => secure.uninstall());

  group('Хранение токенов в secure storage', () {
    test('saveToken → getToken возвращает сохранённое', () async {
      await api.saveToken('abc123');
      expect(await api.getToken(), 'abc123');
      // и реально лёг в защищённое хранилище
      expect(secure.store['auth_token'], 'abc123');
    });

    test('getToken отдаёт из кэша без обращения к хранилищу', () async {
      await api.saveToken('cached');
      secure.store.clear(); // выбили хранилище из-под ног
      // значение всё ещё в in-memory кэше
      expect(await api.getToken(), 'cached');
    });

    test('isLoggedIn: true при наличии токена, false после очистки', () async {
      expect(await api.isLoggedIn(), isFalse);
      await api.saveToken('t');
      expect(await api.isLoggedIn(), isTrue);
      await api.clearAllTokens();
      expect(await api.isLoggedIn(), isFalse);
    });

    test('clearAllTokens чистит и токен, и refresh', () async {
      await api.saveToken('t');
      await api.saveRefreshToken('r');
      await api.clearAllTokens();
      expect(await api.getToken(), isNull);
      expect(await api.getRefreshToken(), isNull);
      expect(secure.store, isEmpty);
    });
  });

  group('Миграция из SharedPreferences (старые версии)', () {
    test('legacy-токен переносится в secure storage и удаляется из prefs',
        () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      });
      api.resetForTesting();

      // Первое же чтение должно подхватить старый токен
      expect(await api.getToken(), 'legacy-access');
      expect(await api.getRefreshToken(), 'legacy-refresh');

      // и перенести его в secure storage
      expect(secure.store['auth_token'], 'legacy-access');
      expect(secure.store['refresh_token'], 'legacy-refresh');

      // удалив из небезопасных prefs
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('без legacy-токена getToken возвращает null', () async {
      expect(await api.getToken(), isNull);
      expect(secure.store, isEmpty);
    });

    test('миграция одноразовая: повторный legacy после неё не подхватывается',
        () async {
      // первый прогон миграции — хранилище пустое, legacy нет
      expect(await api.getToken(), isNull);

      // появился новый legacy-токен (теоретически — прерванная установка),
      // но _migration уже отработала и мемоизирована: повторно не сканируем
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', 'late-legacy');

      expect(await api.getToken(), isNull);
      // legacy так и остался в небезопасных prefs (его никто не трогал)
      expect(prefs.getString('auth_token'), 'late-legacy');
    });
  });
}
