import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../../../services/api_service.dart';

class _OcrCandidate {
  const _OcrCandidate({
    required this.text,
    required this.source,
    required this.score,
  });

  final String text;
  final String source;
  final double score;
}

/// Единая обёртка над OCR для всего приложения.
///
/// Стратегия распознавания:
///  1. Tesseract OCR (rus+eng) — поддерживает кириллицу.
///  2. Fallback на Google ML Kit Latin — если Tesseract вернул пустую строку
///     или завершился с ошибкой.
class RecognitionApi {
  static final TextRecognizer _mlKitRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

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
      debugPrint(
        'RecognitionApi: не удалось сохранить байты во временный файл: $e',
      );
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
    final candidates = <_OcrCandidate>[];

    if (filePath != null) {
      final cloudText = await _recognizeTextWithCloud(filePath);
      if (cloudText != null && cloudText.isNotEmpty) {
        return cloudText;
      }

      final variants = await _prepareOcrImageVariants(filePath);

      for (final variant in variants) {
        await _addTesseractCandidate(
          candidates,
          path: variant,
          psm: '6',
          source: 'tesseract psm=6',
        );
      }

      for (final variant in variants.skip(1)) {
        await _addTesseractCandidate(
          candidates,
          path: variant,
          psm: '11',
          source: 'tesseract sparse',
        );
      }

      final bestScore = candidates.isEmpty
          ? 0.0
          : candidates
                .map((candidate) => candidate.score)
                .reduce((a, b) => a > b ? a : b);
      if (candidates.isEmpty || bestScore < 24) {
        await _addTesseractCandidate(
          candidates,
          path: filePath,
          psm: '3',
          source: 'tesseract auto-page',
        );
      }
    } else {
      debugPrint('RecognitionApi: не удалось получить путь к файлу');
    }

    try {
      final recognized = await _mlKitRecognizer.processImage(inputImage);
      _addCandidate(candidates, recognized.text, 'mlkit latin');
    } catch (e) {
      debugPrint('RecognitionApi: ML Kit ошибка: $e');
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;
    final merged = _mergeBestLines(candidates);
    debugPrint(
      'RecognitionApi: selected ${best.source}, score=${best.score.toStringAsFixed(1)}, length=${merged.length}',
    );
    return merged.isNotEmpty ? merged : best.text;
  }

  static Future<String?> _recognizeTextWithCloud(String filePath) async {
    try {
      final payload = await _prepareCloudOcrPayload(filePath);
      final response = await ApiService().dio.post(
        '/ai/ocr',
        data: payload,
        options: Options(
          sendTimeout: const Duration(seconds: 45),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final text = response.data?['text'];
      if (text is! String) return null;

      final cleaned = _cleanupCloudOcrText(text);
      if (cleaned.isEmpty) return null;

      debugPrint(
        'RecognitionApi: selected openrouter cloud OCR, length=${cleaned.length}',
      );
      return cleaned;
    } on DioException catch (e) {
      debugPrint(
        'RecognitionApi: cloud OCR fallback, status=${e.response?.statusCode}, type=${e.type}',
      );
      return null;
    } catch (e) {
      debugPrint('RecognitionApi: cloud OCR fallback: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> _prepareCloudOcrPayload(
    String filePath,
  ) async {
    final file = File(filePath);
    final originalBytes = await file.readAsBytes();
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      return {
        'imageBase64': base64Encode(originalBytes),
        'mimeType': _mimeTypeForPath(filePath),
      };
    }

    final oriented = img.bakeOrientation(decoded);
    final resized = _resizeForCloudOcr(oriented);
    final jpgBytes = img.encodeJpg(resized, quality: 88);
    return {'imageBase64': base64Encode(jpgBytes), 'mimeType': 'image/jpeg'};
  }

  static img.Image _resizeForCloudOcr(img.Image source) {
    const maxSide = 1800;
    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= maxSide) return img.Image.from(source);
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxSide);
    }
    return img.copyResize(source, height: maxSide);
  }

  static String _mimeTypeForPath(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static String _cleanupCloudOcrText(String text) {
    var cleaned = text
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();

    const prefixes = ['recognized text:', 'extracted text:', 'text:', 'ocr:'];
    final lower = cleaned.toLowerCase();
    for (final prefix in prefixes) {
      if (lower.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length).trim();
        break;
      }
    }
    return cleaned;
  }

  static Future<void> _addTesseractCandidate(
    List<_OcrCandidate> candidates, {
    required String path,
    required String psm,
    required String source,
  }) async {
    try {
      final result = await FlutterTesseractOcr.extractText(
        path,
        language: 'rus+eng',
        args: {'psm': psm, 'preserve_interword_spaces': '1'},
      );
      _addCandidate(
        candidates,
        result,
        '$source (${path.split(Platform.pathSeparator).last})',
      );
    } catch (e) {
      debugPrint('RecognitionApi: $source ошибка: $e');
    }
  }

  static void _addCandidate(
    List<_OcrCandidate> candidates,
    String? rawText,
    String source,
  ) {
    final cleaned = _cleanupRecognizedText(rawText ?? '');
    final score = _scoreRecognizedText(cleaned);
    if (cleaned.isEmpty || score < 8) {
      debugPrint(
        'RecognitionApi: rejected $source, score=${score.toStringAsFixed(1)}',
      );
      return;
    }
    debugPrint(
      'RecognitionApi: candidate $source, score=${score.toStringAsFixed(1)}, length=${cleaned.length}',
    );
    candidates.add(_OcrCandidate(text: cleaned, source: source, score: score));
  }

  static Future<List<String>> _prepareOcrImageVariants(String filePath) async {
    final variants = <String>[filePath];

    try {
      final bytes = await File(filePath).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return variants;

      decoded = img.bakeOrientation(decoded);
      final base = _resizeForOcr(decoded);
      final tempDir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;

      final enhanced = img.Image.from(base);
      img.grayscale(enhanced);
      img.normalize(enhanced, min: 0, max: 255);
      img.adjustColor(enhanced, contrast: 1.35, brightness: 1.05);
      variants.add(
        await _writeOcrVariant(tempDir, 'enhanced_$stamp.jpg', enhanced),
      );

      final crop = _centerCropForText(base);
      img.grayscale(crop);
      img.normalize(crop, min: 0, max: 255);
      img.adjustColor(crop, contrast: 1.45, brightness: 1.08);
      variants.add(await _writeOcrVariant(tempDir, 'crop_$stamp.jpg', crop));
    } catch (e) {
      debugPrint('RecognitionApi: OCR preprocessing error: $e');
    }

    return variants;
  }

  static img.Image _resizeForOcr(img.Image source) {
    final longest = source.width > source.height ? source.width : source.height;
    if (longest < 1500) {
      if (source.width >= source.height) {
        return img.copyResize(source, width: 1500);
      }
      return img.copyResize(source, height: 1500);
    }
    if (longest > 2200) {
      if (source.width >= source.height) {
        return img.copyResize(source, width: 2200);
      }
      return img.copyResize(source, height: 2200);
    }
    return img.Image.from(source);
  }

  static img.Image _centerCropForText(img.Image source) {
    final cropWidth = (source.width * 0.86).round();
    final cropHeight = (source.height * 0.76).round();
    final x = ((source.width - cropWidth) / 2).round();
    final y = ((source.height - cropHeight) / 2).round();
    return img.copyCrop(
      source,
      x: x,
      y: y,
      width: cropWidth,
      height: cropHeight,
    );
  }

  static Future<String> _writeOcrVariant(
    Directory tempDir,
    String name,
    img.Image image,
  ) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(img.encodeJpg(image, quality: 94));
    return file.path;
  }

  static String _cleanupRecognizedText(String text) {
    final lines = text
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'[ ]{2,}'), ' ')
        .split(RegExp(r'\r?\n'))
        .map(_normalizeOcrLine)
        .where(_isUsefulOcrLine)
        .toList();

    final deduped = <String>[];
    for (final line in lines) {
      if (deduped.isEmpty || deduped.last.toLowerCase() != line.toLowerCase()) {
        deduped.add(line);
      }
    }
    return deduped.join('\n').trim();
  }

  static String _mergeBestLines(List<_OcrCandidate> candidates) {
    final selected = <String>[];
    final selectedKeys = <String>{};

    for (final candidate in candidates) {
      for (final rawLine in candidate.text.split('\n')) {
        final line = _normalizeOcrLine(rawLine);
        if (!_isUsefulOcrLine(line)) continue;
        if (_lineQualityScore(line) < 12) continue;

        final key = _lineKey(line);
        if (key.isEmpty || selectedKeys.contains(key)) continue;
        if (selectedKeys.any(
          (existing) => _looksSimilarLineKey(existing, key),
        )) {
          continue;
        }

        selected.add(line);
        selectedKeys.add(key);
      }
    }

    selected.sort((a, b) {
      final aBrand = _isBrandLikeLine(a);
      final bBrand = _isBrandLikeLine(b);
      if (aBrand != bBrand) return aBrand ? -1 : 1;
      return 0;
    });

    return selected.join('\n').trim();
  }

  static String _lineKey(String line) {
    return line.toLowerCase().replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9]'), '');
  }

  static bool _looksSimilarLineKey(String a, String b) {
    if (a == b) return true;
    if (a.length < 5 || b.length < 5) return false;
    return a.contains(b) || b.contains(a);
  }

  static bool _isBrandLikeLine(String line) {
    final compact = line.replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ]'), '');
    if (compact.length < 5 || compact.length > 24) return false;
    return compact == compact.toUpperCase();
  }

  static String _normalizeOcrLine(String line) {
    var normalized = line
        .replaceAll(RegExp(r'[|<>]+'), ' ')
        .replaceAll(RegExp(r'[_=~`{}[\]\\]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final hasCyrillic = RegExp(r'[а-яА-ЯёЁ]').hasMatch(normalized);
    if (hasCyrillic) {
      final tokens = normalized.split(' ');
      normalized = tokens
          .where((token) {
            final cleaned = token.replaceAll(
              RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9]'),
              '',
            );
            if (cleaned.isEmpty) return false;
            final isShortLatin = RegExp(r'^[a-zA-Z]{1,2}$').hasMatch(cleaned);
            final isLowerLatinWord = RegExp(r'^[a-z]{3,}$').hasMatch(cleaned);
            return !isShortLatin && !isLowerLatinWord;
          })
          .join(' ');
    }

    return normalized
        .replaceAll(RegExp(r"""^[\s.,:;!?%№#()/"'«»+-]+"""), '')
        .replaceAll(RegExp(r"""[\s.,:;!?%№#()/"'«»+-]+$"""), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isUsefulOcrLine(String line) {
    if (line.isEmpty) return false;
    final letters = _letterRegex.allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    if (letters == 0 && digits < 2) return false;
    if (line.length <= 2 && letters < 2) return false;

    final cyrillic = RegExp(r'[а-яА-ЯёЁ]').allMatches(line).length;
    final latin = RegExp(r'[a-zA-Z]').allMatches(line).length;
    final words = RegExp(r'[a-zA-Zа-яА-ЯёЁ]{2,}').allMatches(line).toList();
    final goodWords = RegExp(r'[a-zA-Zа-яА-ЯёЁ]{3,}').allMatches(line).length;
    final singleTokens = RegExp(
      r'(^|\s)[a-zA-Zа-яА-ЯёЁ0-9](?=\s|$)',
    ).allMatches(line).length;
    final mixedScriptWords = RegExp(
      r'(?=[a-zA-Zа-яА-ЯёЁ]*[a-zA-Z])(?=[a-zA-Zа-яА-ЯёЁ]*[а-яА-ЯёЁ])[a-zA-Zа-яА-ЯёЁ]{3,}',
    ).allMatches(line).length;
    final uppercaseAcronyms = RegExp(
      r'\b[A-ZА-ЯЁ]{4,}\b',
    ).allMatches(line).length;

    if (mixedScriptWords > 0) return false;
    if (cyrillic > 0 &&
        latin == 0 &&
        digits == 0 &&
        line.length <= 4 &&
        uppercaseAcronyms == 0) {
      return false;
    }
    if (cyrillic > 0 &&
        latin == 0 &&
        digits == 0 &&
        words.length >= 2 &&
        !RegExp(r'[а-яА-ЯёЁ]{7,}').hasMatch(line)) {
      return false;
    }
    if (singleTokens >= 2 && goodWords < 2) return false;
    if (cyrillic > 0 && latin > cyrillic) return false;
    if (goodWords == 0 && digits < 2) return false;
    if (cyrillic == 0 && words.length >= 2 && uppercaseAcronyms == 0) {
      final totalWordLength = words.fold<int>(
        0,
        (sum, match) => sum + match.group(0)!.length,
      );
      final averageWordLength = totalWordLength / words.length;
      if (averageWordLength < 4.2) return false;
    }

    final junk = RegExp(
      r'''[^a-zA-Zа-яА-ЯёЁ0-9\s.,:;!?%№#()/"'«»+\-]''',
    ).allMatches(line).length;
    final useful = letters + digits;
    if (useful == 0) return false;
    return junk / line.length < 0.36;
  }

  static double _lineQualityScore(String line) {
    final letters = _letterRegex.allMatches(line).length;
    final cyrillic = RegExp(r'[а-яА-ЯёЁ]').allMatches(line).length;
    final latin = RegExp(r'[a-zA-Z]').allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    final words = RegExp(r'[a-zA-Zа-яА-ЯёЁ]{3,}').allMatches(line).length;
    final junk = RegExp(
      r'''[^a-zA-Zа-яА-ЯёЁ0-9\s.,:;!?%№#()/"'«»+\-]''',
    ).allMatches(line).length;
    final singleTokens = RegExp(
      r'(^|\s)[a-zA-Zа-яА-ЯёЁ0-9](?=\s|$)',
    ).allMatches(line).length;

    var score = letters * 1.5 + words * 5 + digits * 0.25;
    if (_isBrandLikeLine(line)) score += 10;
    if (cyrillic > 0 && latin == 0) score += 4;
    score -= junk * 7;
    score -= singleTokens * 4;
    return score;
  }

  static double _scoreRecognizedText(String text) {
    if (text.trim().isEmpty || !_letterRegex.hasMatch(text)) return 0;
    final letters = _letterRegex.allMatches(text).length;
    final cyrillic = RegExp(r'[а-яА-ЯёЁ]').allMatches(text).length;
    final digits = RegExp(r'\d').allMatches(text).length;
    final words = RegExp(r'[a-zA-Zа-яА-ЯёЁ]{3,}').allMatches(text).length;
    final lines = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .length;
    final junk = RegExp(
      r'''[^a-zA-Zа-яА-ЯёЁ0-9\s.,:;!?%№#()/"'«»+\-]''',
    ).allMatches(text).length;
    final isolated = RegExp(
      r'(^|\s)[a-zA-Zа-яА-ЯёЁ0-9](?=\s|$)',
    ).allMatches(text).length;

    return letters * 1.8 +
        cyrillic * 0.9 +
        digits * 0.35 +
        words * 6 +
        lines * 2 -
        junk * 7 -
        isolated * 2.5;
  }

  static Future<void> dispose() async {
    await _mlKitRecognizer.close();
  }
}
