import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:path_provider/path_provider.dart';

/// Единая обёртка над OCR для всего приложения.
///
/// Стратегия распознавания:
///  1. Tesseract OCR (rus+eng) — поддерживает кириллицу.
///  2. Fallback на Google ML Kit Latin — если Tesseract вернул пустую строку
///     или завершился с ошибкой.
class RecognitionApi {
  static final TextRecognizer _mlKitRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Извлекает путь к файлу из [InputImage].
  ///
  /// Если [InputImage] создан через [InputImage.fromFilePath] — возвращает
  /// этот путь напрямую. Иначе сохраняет байты во временный файл и возвращает
  /// его путь. Возвращает `null`, если достать данные невозможно.
  static Future<String?> _resolveFilePath(InputImage inputImage) async {
    // InputImage хранит путь в поле filePath (доступно через metadata или
    // через приватное поле). Самый надёжный способ — проверить filePath,
    // который доступен как геттер начиная с google_mlkit_commons 0.6+.
    try {
      final path = inputImage.filePath;
      if (path != null && path.isNotEmpty) {
        return path;
      }
    } catch (_) {
      // Поле недоступно в текущей версии пакета — продолжаем.
    }

    // Если путь недоступен, пробуем сохранить байты во временный файл.
    try {
      final bytes = inputImage.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/ocr_temp_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await tempFile.writeAsBytes(bytes);
        return tempFile.path;
      }
    } catch (e) {
      debugPrint('RecognitionApi: не удалось сохранить байты во временный файл: $e');
    }

    return null;
  }

  static final _letterRegex = RegExp(r'[a-zA-Zа-яА-ЯёЁ]');

  /// Распознаёт текст из [inputImage].
  ///
  /// Стратегия:
  ///  1. Tesseract (rus+eng, psm 6) — основной, поддерживает кириллицу.
  ///  2. Tesseract (rus+eng, psm 3) — повторная попытка с авто-разбивкой.
  ///  3. ML Kit Latin — fallback только для латиницы (кириллицу не даст).
  static Future<String?> recognizeText(InputImage inputImage) async {
    final filePath = await _resolveFilePath(inputImage);

    // --- 1. Tesseract psm=6 (однородный блок текста) ---
    if (filePath != null) {
      try {
        final result = await FlutterTesseractOcr.extractText(
          filePath,
          language: 'rus+eng',
          args: {'psm': '6', 'preserve_interword_spaces': '1'},
        );
        final trimmed = result.trim();
        if (trimmed.isNotEmpty && _letterRegex.hasMatch(trimmed)) {
          debugPrint('RecognitionApi: Tesseract psm=6 (${trimmed.length} символов)');
          return trimmed;
        }
      } catch (e) {
        debugPrint('RecognitionApi: Tesseract psm=6 ошибка: $e');
      }

      // --- 2. Tesseract psm=3 (автоматический разбор страницы) ---
      try {
        final result = await FlutterTesseractOcr.extractText(
          filePath,
          language: 'rus+eng',
          args: {'psm': '3', 'preserve_interword_spaces': '1'},
        );
        final trimmed = result.trim();
        if (trimmed.isNotEmpty && _letterRegex.hasMatch(trimmed)) {
          debugPrint('RecognitionApi: Tesseract psm=3 (${trimmed.length} символов)');
          return trimmed;
        }
        debugPrint('RecognitionApi: Tesseract вернул пустой результат');
      } catch (e) {
        debugPrint('RecognitionApi: Tesseract psm=3 ошибка: $e');
      }
    } else {
      debugPrint('RecognitionApi: не удалось получить путь к файлу');
    }

    // --- 3. Fallback: ML Kit Latin (только для латиницы) ---
    try {
      final recognized = await _mlKitRecognizer.processImage(inputImage);
      final text = recognized.text.trim();
      if (text.isNotEmpty && _letterRegex.hasMatch(text)) {
        debugPrint('RecognitionApi: ML Kit Latin (${text.length} символов)');
        return text;
      }
    } catch (e) {
      debugPrint('RecognitionApi: ML Kit ошибка: $e');
    }

    return null;
  }

  static Future<void> dispose() async {
    await _mlKitRecognizer.close();
  }
}
