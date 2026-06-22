import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'api_service.dart';

/// Категория ошибки AI-анализа — экран маппит её в локализованный текст,
/// чтобы пользователь не видел сырой DioException.
enum AiErrorKind { unavailable, timeout, generic }

class AiException implements Exception {
  final AiErrorKind kind;
  AiException(this.kind);
}

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
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
          },
          {'type': 'text', 'text': customPrompt ?? _defaultPrompt},
        ],
      },
    ]);
  }

  Future<String> analyzeText(String text, {String? customPrompt}) async {
    final prompt =
        (customPrompt ??
            'Ты — помощник для анализа документов. Проанализируй этот текст и:\n'
                '1. Извлеки суть (1-2 предложения)\n'
                '2. Выдели ключевые моменты\n'
                '3. Определи необходимые действия\n'
                '4. Укажи важные даты и сроки\n'
                'Отвечай на русском языке. Используй эмодзи для структуры.\n\n'
                'Текст документа:\n') +
        text;

    return _send([
      {'role': 'user', 'content': prompt},
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
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
          },
          {'type': 'text', 'text': _ecoPrompt},
        ],
      },
    ]);
  }

  /// Восстановление старого фото через сервер (Replicate/GFPGAN). Отправляет
  /// картинку как base64, получает URL восстановленного файла, скачивает его
  /// и возвращает локальный временный файл. Бросает [AiException] при сбое —
  /// экран показывает локализованную ошибку и может откатиться на локальное
  /// улучшение.
  /// [fidelity] (0..1) — «сила»/верность лицам для 2-й стадии (CodeFormer):
  /// ближе к 1 = натуральнее, ближе к 0 = чётче. null → дефолт сервера.
  Future<File> restorePhoto(File imageFile, {double? fidelity}) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.toLowerCase();
    final mimeType = ext.endsWith('.png') ? 'image/png' : 'image/jpeg';

    try {
      final response = await ApiService().dio.post(
        '/ai/restore',
        data: {
          'imageBase64': base64Image,
          'mimeType': mimeType,
          if (fidelity != null) 'fidelity': fidelity,
        },
        // Модель на Replicate может «холодно стартовать» десятки секунд —
        // даём щедрый receiveTimeout, чтобы не падать раньше сервера.
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 150),
        ),
      );
      final url = response.data?['url'];
      if (url is! String || url.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }

      // Скачиваем восстановленное фото (абсолютный URL CDN Replicate —
      // dio не подставляет baseUrl, т.к. путь начинается с https://).
      final download = await ApiService().dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = download.data;
      if (data == null || data.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }

      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/airestore_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(out);
      await file.writeAsBytes(data);
      return file;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw AiException(AiErrorKind.timeout);
      }
      final status = e.response?.statusCode ?? 0;
      if (status >= 500 || status == 0) {
        throw AiException(AiErrorKind.unavailable);
      }
      throw AiException(AiErrorKind.generic);
    }
  }

  /// Uses semantic inpainting for the selected watermark regions. White mask
  /// pixels are rebuilt by the server; all other pixels are preserved.
  Future<Uint8List> removeWatermarks(
    Uint8List imageBytes,
    List<Rect> normalizedRegions,
  ) async {
    final source = img.decodeImage(imageBytes);
    if (source == null || normalizedRegions.isEmpty) {
      throw AiException(AiErrorKind.generic);
    }

    final mask = img.Image(width: source.width, height: source.height);
    img.fill(mask, color: img.ColorRgb8(0, 0, 0));
    for (final region in normalizedRegions) {
      final padded = region.inflate(0.004);
      final left = (padded.left.clamp(0.0, 1.0) * source.width).floor();
      final top = (padded.top.clamp(0.0, 1.0) * source.height).floor();
      final right = (padded.right.clamp(0.0, 1.0) * source.width).ceil() - 1;
      final bottom = (padded.bottom.clamp(0.0, 1.0) * source.height).ceil() - 1;
      if (right <= left || bottom <= top) continue;
      img.fillRect(
        mask,
        x1: left,
        y1: top,
        x2: right,
        y2: bottom,
        color: img.ColorRgb8(255, 255, 255),
      );
    }

    final encodedImage = img.encodeJpg(source, quality: 95);
    final encodedMask = img.encodePng(mask);
    try {
      final response = await ApiService().dio.post(
        '/ai/remove-watermarks',
        data: {
          'imageBase64': base64Encode(encodedImage),
          'imageMimeType': 'image/jpeg',
          'maskBase64': base64Encode(encodedMask),
        },
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 150),
        ),
      );
      final url = response.data?['url'];
      if (url is! String || url.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }

      final download = await ApiService().dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final result = download.data;
      if (result == null || result.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }
      return Uint8List.fromList(result);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw AiException(AiErrorKind.timeout);
      }
      final status = e.response?.statusCode ?? 0;
      if (status >= 500 || status == 0) {
        throw AiException(AiErrorKind.unavailable);
      }
      throw AiException(AiErrorKind.generic);
    }
  }

  /// Удаление водяного знака со ВСЕГО кадра без маски (FLUX Kontext). Подходит
  /// для сплошных/тайловых знаков, перекрывающих всю картинку, где маска-
  /// инпейнтинг бессилен. Принимает JPEG-байты, возвращает результат.
  Future<Uint8List> dewatermark(Uint8List jpegBytes) async {
    final base64Image = base64Encode(jpegBytes);
    try {
      final response = await ApiService().dio.post(
        '/ai/dewatermark',
        data: {'imageBase64': base64Image, 'mimeType': 'image/jpeg'},
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 150),
        ),
      );
      final url = response.data?['url'];
      if (url is! String || url.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }
      final download = await ApiService().dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = download.data;
      if (data == null || data.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw AiException(AiErrorKind.timeout);
      }
      final status = e.response?.statusCode ?? 0;
      if (status >= 500 || status == 0) {
        throw AiException(AiErrorKind.unavailable);
      }
      throw AiException(AiErrorKind.generic);
    }
  }

  Future<String> _send(List<Map<String, dynamic>> messages) async {
    try {
      final response = await ApiService().dio.post(
        // baseUrl уже заканчивается на /api (ServerConfig), поэтому путь
        // БЕЗ префикса /api — иначе получался двойной /api/api/ai/analyze
        // и сервер отвечал 404 (как все остальные вызовы: /auth, /documents).
        '/ai/analyze',
        data: {'messages': messages},
        // AI обращается к внешнему OpenRouter, у которого периодически висит upstream.
        // Без таймаута клиент висит вечно — лучше упасть через 90 секунд.
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final result = response.data?['result'];
      if (result is! String || result.isEmpty) {
        throw AiException(AiErrorKind.generic);
      }
      return result;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        throw AiException(AiErrorKind.timeout);
      }
      final status = e.response?.statusCode ?? 0;
      // 5xx / 0 (нет связи) — сервис недоступен; остальное — общая ошибка.
      if (status >= 500 || status == 0) {
        throw AiException(AiErrorKind.unavailable);
      }
      throw AiException(AiErrorKind.generic);
    }
  }
}
