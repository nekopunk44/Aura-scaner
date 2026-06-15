import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scanner_ap/config/server_config.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfig().load();
  });

  group('ServerConfig — значения по умолчанию', () {
    test('baseUrl равен defaultServerUrl после load() с пустым хранилищем', () {
      expect(ServerConfig().baseUrl, defaultServerUrl);
    });

    test('defaultServerUrl — продакшен по HTTPS, не локальный дев-адрес', () {
      expect(defaultServerUrl, startsWith('https://'));
      expect(defaultServerUrl, isNot(contains('localhost')));
      expect(defaultServerUrl, isNot(contains('10.0.2.2')));
    });
  });

  group('ServerConfig — сохранение и загрузка', () {
    test('save() сохраняет URL и baseUrl обновляется сразу', () async {
      await ServerConfig().save('http://192.168.1.10:3000/api');
      expect(ServerConfig().baseUrl, 'http://192.168.1.10:3000/api');
    });

    test('load() восстанавливает ранее сохранённый URL', () async {
      const saved = 'http://10.0.2.2:3000/api';
      SharedPreferences.setMockInitialValues({'server_url': saved});
      await ServerConfig().load();
      expect(ServerConfig().baseUrl, saved);
    });

    test('load() возвращает defaultServerUrl если ничего не сохранено', () async {
      SharedPreferences.setMockInitialValues({});
      await ServerConfig().load();
      expect(ServerConfig().baseUrl, defaultServerUrl);
    });
  });

  group('ServerConfig — нормализация URL', () {
    test('save() убирает завершающий слэш', () async {
      await ServerConfig().save('http://192.168.1.1:3000/api/');
      expect(ServerConfig().baseUrl, 'http://192.168.1.1:3000/api');
    });

    test('save() убирает несколько завершающих слэшей', () async {
      await ServerConfig().save('http://192.168.1.1:3000/api///');
      expect(ServerConfig().baseUrl, 'http://192.168.1.1:3000/api');
    });

    test('save() обрезает пробелы справа', () async {
      await ServerConfig().save('http://192.168.1.1:3000/api   ');
      expect(ServerConfig().baseUrl, 'http://192.168.1.1:3000/api');
    });

    test('URL без слэша не меняется', () async {
      const url = 'http://localhost:3000/api';
      await ServerConfig().save(url);
      expect(ServerConfig().baseUrl, url);
    });
  });
}
