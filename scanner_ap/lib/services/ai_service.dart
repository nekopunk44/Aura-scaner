import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'api_service.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  static const _defaultPrompt =
      'Ты — помощник для анализа документов. Проанализируй этот документ и:\n'
      '1. Извлеки суть документа (1-2 предложения)\n'
      '2. Выдели ключевые моменты и важные условия\n'
      '3. Определи необходимые действия (если есть)\n'
      '4. Укажи важные даты и сроки (если есть)\n'
      'Отвечай на русском языке. Используй эмодзи для структуры.';

  static const _ecoPrompt =
      'Проанализируй упаковку на фото с точки зрения экологичности:\n'
      '1. 🌿 Экологичность материалов\n'
      '2. ♻️ Возможность переработки\n'
      '3. 📦 Состав упаковки (если видно)\n'
      '4. 💡 Рекомендации по утилизации\n'
      '5. ⭐ Общая эко-оценка (1-10)\n'
      'Отвечай на русском языке.';

  Future<String> analyzeDocument(File imageFile, {String? customPrompt}) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.toLowerCase();
    final mimeType = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';

    return _send([
      {
        'role': 'user',
        'content': [
          {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$base64Image'}},
          {'type': 'text', 'text': customPrompt ?? _defaultPrompt},
        ],
      }
    ]);
  }

  Future<String> analyzeText(String text, {String? customPrompt}) async {
    final prompt = (customPrompt ??
            'Ты — помощник для анализа документов. Проанализируй этот текст и:\n'
            '1. Извлеки суть (1-2 предложения)\n'
            '2. Выдели ключевые моменты\n'
            '3. Определи необходимые действия\n'
            '4. Укажи важные даты и сроки\n'
            'Отвечай на русском языке. Используй эмодзи для структуры.\n\n'
            'Текст документа:\n') +
        text;

    return _send([
      {'role': 'user', 'content': prompt}
    ]);
  }

  Future<String> analyzeEcoPackaging(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.toLowerCase();
    final mimeType = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';

    return _send([
      {
        'role': 'user',
        'content': [
          {'type': 'image_url', 'image_url': {'url': 'data:$mimeType;base64,$base64Image'}},
          {'type': 'text', 'text': _ecoPrompt},
        ],
      }
    ]);
  }

  Future<String> _send(List<Map<String, dynamic>> messages) async {
    try {
      final response = await ApiService().dio.post(
        '/api/ai/analyze',
        data: {'messages': messages},
        // AI обращается к внешнему OpenRouter, у которого периодически висит upstream.
        // Без таймаута клиент висит вечно — лучше упасть через 90 секунд.
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final result = response.data?['result'];
      if (result == null) throw Exception('Пустой ответ от AI сервиса');
      if (result is! String) throw Exception('Некорректный формат ответа от AI сервиса');
      if (result.isEmpty) throw Exception('AI сервис вернул пустой результат');
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw Exception('AI сервис не отвечает. Попробуйте позже.');
      }
      rethrow;
    }
  }
}
