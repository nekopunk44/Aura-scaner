import 'package:shared_preferences/shared_preferences.dart';

const _serverUrlKey = 'server_url';

const _presets = {
  'Production (Railway)': 'https://aura-scaner-production.up.railway.app/api',
  'Эмулятор Android': 'http://10.0.2.2:3000/api',
  'Localhost': 'http://localhost:3000/api',
  'Локальная сеть (192.168.x.x)': '',
};

const defaultServerUrl =
    'https://aura-scaner-production.up.railway.app/api';

class ServerConfig {
  static final ServerConfig _instance = ServerConfig._internal();
  factory ServerConfig() => _instance;
  ServerConfig._internal();

  String _baseUrl = defaultServerUrl;

  String get baseUrl => _baseUrl;

  Map<String, String> get presets => _presets;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_serverUrlKey) ?? defaultServerUrl;
  }

  Future<void> save(String url) async {
    _baseUrl = url.trimRight().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, _baseUrl);
  }
}
