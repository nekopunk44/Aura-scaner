import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:scanner_ap/services/premium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PremiumService — синглтон, поэтому перед каждым кейсом приводим его
  // и хранилище к чистому состоянию.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PremiumService().load();
  });

  group('PremiumService.load — чтение из хранилища', () {
    test('пустое хранилище → premium в debug-сборке, без срока', () async {
      expect(PremiumService().isPremium, isTrue);
      expect(PremiumService().expiresAt, isNull);
    });

    test('is_premium=true восстанавливается', () async {
      SharedPreferences.setMockInitialValues({'is_premium': true});
      await PremiumService().load();
      expect(PremiumService().isPremium, isTrue);
    });

    test('срок действия парсится из ISO-строки', () async {
      final expires = DateTime.utc(2030, 1, 2, 3, 4, 5);
      SharedPreferences.setMockInitialValues({
        'is_premium': true,
        'premium_expires_at': expires.toIso8601String(),
      });
      await PremiumService().load();
      expect(PremiumService().expiresAt, expires);
    });

    test('битая дата срока → null, без исключения', () async {
      SharedPreferences.setMockInitialValues({
        'is_premium': true,
        'premium_expires_at': 'не-дата',
      });
      await PremiumService().load();
      expect(PremiumService().expiresAt, isNull);
    });
  });

  group('PremiumService.activate / deactivate', () {
    test('activate включает premium и персистит', () async {
      await PremiumService().activate();
      expect(PremiumService().isPremium, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_premium'), isTrue);
    });

    test('deactivate сбрасывает статус, срок и продукт', () async {
      SharedPreferences.setMockInitialValues({
        'is_premium': true,
        'premium_expires_at': DateTime.utc(2030).toIso8601String(),
        'premium_product_id': 'sub_yearly',
      });
      await PremiumService().load();
      expect(PremiumService().isPremium, isTrue);

      await PremiumService().deactivate();

      expect(PremiumService().isPremium, isFalse);
      expect(PremiumService().expiresAt, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_premium'), isFalse);
      expect(prefs.getString('premium_expires_at'), isNull);
      expect(prefs.getString('premium_product_id'), isNull);
    });

    test('состояние переживает повторный load после activate', () async {
      await PremiumService().activate();
      await PremiumService().load();
      expect(PremiumService().isPremium, isTrue);
    });
  });
}
