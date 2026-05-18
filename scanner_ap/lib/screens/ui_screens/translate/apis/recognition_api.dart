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

  /// Распознаёт текст из [inputImage].
  ///
  /// Сначала пробует Tesseract (rus+eng). При пустом результате или ошибке
  /// переключается на ML Kit Latin.
  static Future<String?> recognizeText(InputImage inputImage) async {
    // --- 1. Попытка через Tesseract ---
    try {
      final filePath = await _resolveFilePath(inputImage);
      if (filePath != null) {
        final tesseractResult = await FlutterTesseractOcr.extractText(
          filePath,
          language: 'rus+eng',
          args: {
            'psm': '6',
            'preserve_interword_spaces': '1',
          },
        );
        final trimmed = tesseractResult.trim();
        if (trimmed.isNotEmpty) {
          debugPrint('RecognitionApi: результат от Tesseract (${trimmed.length} символов)');
          return trimmed;
        }
        debugPrint('RecognitionApi: Tesseract вернул пустую строку, переключаемся на ML Kit');
      } else {
        debugPrint('RecognitionApi: не удалось получить путь к файлу, переключаемся на ML Kit');
      }
    } catch (e) {
      debugPrint('RecognitionApi: ошибка Tesseract, переключаемся на ML Kit: $e');
    }

    // --- 2. Fallback: ML Kit Latin ---
    try {
      final recognizedText = await _mlKitRecognizer.processImage(inputImage);
      final text = recognizedText.text.trim();
      if (text.isNotEmpty) {
        debugPrint('RecognitionApi: результат от ML Kit (${text.length} символов)');
        return text;
      }
      return null;
    } catch (e) {
      debugPrint('RecognitionApi: ошибка ML Kit: $e');
      return null;
    }
  }

  static Future<void> dispose() async {
    await _mlKitRecognizer.close();
  }
}
