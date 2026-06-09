import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class PremiumService {
  static final PremiumService _instance = PremiumService._internal();
  factory PremiumService() => _instance;
  PremiumService._internal();

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool('is_premium') ?? false;
  }

  /// Синхронизирует статус с сервером. Вызывается при старте если пользователь авторизован.
  Future<void> syncWithServer() async {
    try {
      final response = await ApiService().dio.get('/auth/profile');
      final serverPremium = response.data['isPremium'] as bool? ?? false;
      if (serverPremium != _isPremium) {
        _isPremium = serverPremium;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_premium', _isPremium);
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
  }

  Future<void> activate() async {
    _isPremium = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', true);
  }

  Future<void> deactivate() async {
    _isPremium = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', false);
  }
}
