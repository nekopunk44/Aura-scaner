import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';

class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  static const _kAndroidPackage = 'com.aurascanner.app';

  bool _isPremium = false;
  DateTime? _expiresAt;
  String? _activeProductId;

  bool get isPremium => _isPremium;
  DateTime? get expiresAt => _expiresAt;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool('is_premium') ?? kDebugMode;
    final expiresStr = prefs.getString('premium_expires_at');
    _expiresAt = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
    _activeProductId = prefs.getString('premium_product_id');

    // In debug builds we keep Premium enabled by default for local testing.
    if (kDebugMode && !_isPremium) {
      _isPremium = true;
      await prefs.setBool('is_premium', true);
    }
  }

  /// Синхронизирует статус с сервером. Вызывается при старте если пользователь авторизован.
  Future<void> syncWithServer() async {
    if (kDebugMode) {
      return;
    }
    try {
      final response = await ApiService().dio.get('/auth/profile');
      final serverPremium = response.data['isPremium'] as bool? ?? false;
      final expiresRaw = response.data['premiumExpiresAt'] as String?;
      final serverExpires = expiresRaw != null ? DateTime.tryParse(expiresRaw) : null;

      final prefs = await SharedPreferences.getInstance();
      if (serverPremium != _isPremium) {
        _isPremium = serverPremium;
        await prefs.setBool('is_premium', _isPremium);
      }
      if (serverExpires != _expiresAt) {
        _expiresAt = serverExpires;
        if (serverExpires != null) {
          await prefs.setString('premium_expires_at', serverExpires.toIso8601String());
        } else {
          await prefs.remove('premium_expires_at');
        }
      }
    } catch (_) {
      // Оставляем локальный кэш при ошибке сети
    }
  }

  /// Отправляет receipt на сервер для верификации.
  /// Сервер проверит receipt у Apple/Google и активирует Premium только при успехе.
  /// Бросает исключение если сервер отверг покупку.
  Future<void> activateOnServer({
    required String platform,
    required String productId,
    required String receipt,
  }) async {
    final response = await ApiService().dio.post(
      '/premium/activate',
      data: {
        'platform': platform,
        'productId': productId,
        'receipt': receipt,
      },
    );
    final isPremium = response.data?['isPremium'] as bool? ?? false;
    if (!isPremium) {
      throw Exception('Сервер не подтвердил активацию Premium');
    }
    _activeProductId = productId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('premium_product_id', productId);
  }

  Future<void> activate() async {
    _isPremium = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', true);
  }

  Future<void> deactivate() async {
    _isPremium = false;
    _expiresAt = null;
    _activeProductId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', false);
    await prefs.remove('premium_expires_at');
    await prefs.remove('premium_product_id');
  }

  /// Открывает системную страницу управления подписками. Возвращает true,
  /// если URL был успешно запущен. На iOS это страница App Store, на
  /// Android — Play Store (с диплинком на конкретный продукт, если есть).
  Future<bool> openManageSubscription() async {
    final Uri uri;
    if (Platform.isIOS || Platform.isMacOS) {
      uri = Uri.parse('https://apps.apple.com/account/subscriptions');
    } else if (Platform.isAndroid) {
      final base = 'https://play.google.com/store/account/subscriptions';
      final productId = _activeProductId;
      uri = productId != null
          ? Uri.parse('$base?sku=$productId&package=$_kAndroidPackage')
          : Uri.parse(base);
    } else {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
