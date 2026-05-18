import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:docx_to_text/docx_to_text.dart';

/// Миксин с утилитами для генерации превью документов.
///
/// Подключается к MyDocumentsScreen для отображения миниатюр файлов.
///
/// Поддерживаемые форматы:
/// - **PDF** — рендерит первую страницу через pdfx
/// - **DOCX** — извлекает текст и рисует его на Canvas
/// - **JPG/PNG** — использует Image.file напрямую
/// - **TXT** — читает первые строки и рисует на Canvas
///
/// Кэширование: превью генерируются один раз и хранятся в памяти.
/// Кэш не очищается автоматически; при необходимости стоит добавить LRU или очистку по размеру.
///
/// Известная проблема: `bool get mounted => true` захардкожен,
/// что может вызвать setState после dispose. Нужно переопределять в классе-хосте.
mixin DocumentUtils {
  final Map<String, Uint8List?> _pdfPreviewCache = {};
  final Map<String, Uint8List?> _docxPreviewCache = {};
  final Map<String, bool> _pdfLoadingFlags = {};
  final Map<String, bool> _docxLoadingFlags = {};
  final _random = Random();

  bool get mounted => true;

  void updateState() {}

  String getFileNameFromPath(String path) {
    return path.split('/').last;
  }

  void removeFromCache(String filePath) {
    _pdfPreviewCache.remove(filePath);
    _docxPreviewCache.remove(filePath);
    _pdfLoadingFlags.remove(filePath);
    _docxLoadingFlags.remove(filePath);
  }

  void updateCachePath(String oldPath, String newPath) {
    if (_pdfPreviewCache.containsKey(oldPath)) {
      _pdfPreviewCache[newPath] = _pdfPreviewCache[oldPath];
      _pdfPreviewCache.remove(oldPath);
    }
    if (_docxPreviewCache.containsKey(oldPath)) {
      _docxPreviewCache[newPath] = _docxPreviewCache[oldPath];
      _docxPreviewCache.remove(oldPath);
    }
    if (_pdfLoadingFlags.containsKey(oldPath)) {
      _pdfLoadingFlags[newPath] = _pdfLoadingFlags[oldPath]!;
      _pdfLoadingFlags.remove(oldPath);
    }
    if (_docxLoadingFlags.containsKey(oldPath)) {
      _docxLoadingFlags[newPath] = _docxLoadingFlags[oldPath]!;
      _docxLoadingFlags.remove(oldPath);
    }
  }

  Future<String> _extractTextFromDocxBytes(Uint8List bytes) async {
    try {
      final text = docxToText(bytes);

      String cleanText = text.replaceAll(RegExp(r'[^\w\s\p{P}А-Яа-яЁё]'), ' ');
      cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();

      final totalChars = cleanText.length;
      final alphaNumericChars = cleanText.replaceAll(RegExp(r'[^a-zA-Zа-яА-Я0-9]'), '').length;

      if (totalChars > 50 && alphaNumericChars / totalChars < 0.10) {
        return 'ОШИБКА ОЧИСТКИ: Извлеченный текст состоит в основном из нечитаемых символов. Документ может быть поврежден.';
      }

      if (cleanText.isEmpty) {
        return 'Документ не содержит читаемого текста.';
      }

      return cleanText;

    } catch (e) {
      debugPrint('Критическая ошибка извлечения текста из DOCX: $e');
      return 'КРИТИЧЕСКАЯ ОШИБКА: Не удалось прочитать файл DOCX. Документ, возможно, не является корректным DOCX-файлом.';
    }
  }

  Future<Uint8List?> generatePdfPreview(String filePath) async {
    if (_pdfLoadingFlags[filePath] == true) {
      return null;
    }

    if (_pdfPreviewCache.containsKey(filePath)) {
      return _pdfPreviewCache[filePath];
    }

    try {
      _pdfLoadingFlags[filePath] = true;

      final document = await PdfDocument.openFile(filePath);
      final page = await document.getPage(1);

      final pageImage = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
      );

      await page.close();
      await document.close();

      final result = pageImage?.bytes;
      _pdfPreviewCache[filePath] = result;
      _pdfLoadingFlags[filePath] = false;

      updateState();

      return result;
    } catch (e) {
      debugPrint('Ошибка создания превью PDF: $e');
      _pdfPreviewCache[filePath] = null;
      _pdfLoadingFlags[filePath] = false;
      return null;
    }
  }

  Future<Uint8List?> generateDocxPreview(String filePath) async {
    if (_docxLoadingFlags[filePath] == true) {
      return null;
    }

    if (_docxPreviewCache.containsKey(filePath)) {
      return _docxPreviewCache[filePath];
    }

    try {
      _docxLoadingFlags[filePath] = true;

      final file = File(filePath);
      if (!await file.exists()) {
        final errorPreview = await _createErrorPreview();
        _docxPreviewCache[filePath] = errorPreview;
        _docxLoadingFlags[filePath] = false;
        return errorPreview;
      }

      String realContent = '';

      try {
        final bytes = await file.readAsBytes();
        realContent = await _extractTextFromDocxBytes(bytes);

        if (realContent.isEmpty) {
          realContent = 'Документ не содержит видимого текста.';
        }

      } catch (e) {
      debugPrint('Ошибка чтения или парсинга DOCX файла $filePath: $e');
        realContent = 'Ошибка чтения документа';
      }

      final previewImage = await _createRealDocxPreviewImage(realContent, filePath);

      _docxPreviewCache[filePath] = previewImage;
      _docxLoadingFlags[filePath] = false;

      updateState();

      return previewImage;
    } catch (e) {
      debugPrint('Ошибка создания превью DOCX: $e');
      final errorPreview = await _createErrorPreview();
      _docxLoadingFlags[filePath] = false;
      return errorPreview;
    }
  }

  Future<Uint8List?> _createRealDocxPreviewImage(String realContent, String filePath) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = Size(120, 80);

      final backgroundPaint = Paint()..color = Colors.white;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

      final contentStyle = const TextStyle(
        color: Colors.black,
        fontSize: 4,
        height: 1.2,
      );

      String previewText = realContent.trim();

      if (previewText.isEmpty) {
        const String baseFillerText =
            "Это пустой документ. Содержимое появится после редактирования. DOCX распознан.";

        final int targetLines = _random.nextInt(9) + 2;
        final StringBuffer buffer = StringBuffer();

        for (int i = 0; i < targetLines; i++) {
          final int minLen = 30;
          final int maxLen = 60;
          final int randomLength = _random.nextInt(maxLen - minLen) + minLen;

          buffer.write(baseFillerText.substring(0, min(baseFillerText.length, randomLength)));
          buffer.write('\n');

          if (_random.nextDouble() < 0.25) {
            buffer.write('\n');
          }
        }

        previewText = buffer.toString().trim();
      }

      const int maxDisplayCharacters = 2000;
      if (previewText.length > maxDisplayCharacters) {
        previewText = '${previewText.substring(0, maxDisplayCharacters)}...';
      }

      const int veryLargeMaxLines = 1000;
      final contentPainter = TextPainter(
        text: TextSpan(text: previewText, style: contentStyle),
        textDirection: TextDirection.ltr,
        maxLines: veryLargeMaxLines,
        ellipsis: '...',
      );

      final double padding = 4.0;
      contentPainter.layout(maxWidth: size.width - (padding * 2));
      contentPainter.paint(canvas, Offset(padding, padding));

      final borderPaint = Paint()
        ..color = Colors.blue.shade400
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRect(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        borderPaint,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Ошибка создания реального превью DOCX: $e');
      return _createErrorPreview();
    }
  }

  Future<Uint8List?> _createErrorPreview() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(40, 40);

    final backgroundPaint = Paint()..color = Colors.grey.shade300;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData?.buffer.asUint8List();
  }

  Widget buildFileThumbnail(String filePath) {
    final fileName = getFileNameFromPath(filePath).toLowerCase();

    if (fileName.endsWith('.jpg') || fileName.endsWith('.png') || fileName.endsWith('.jpeg')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6.0),
        child: Image.file(
          File(filePath),
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildErrorIcon();
          },
        ),
      );
    } else if (fileName.endsWith('.pdf')) {
      if (_pdfPreviewCache.containsKey(filePath) && _pdfPreviewCache[filePath] != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Image.memory(
            _pdfPreviewCache[filePath]!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      }

      return FutureBuilder<Uint8List?>(
        future: generatePdfPreview(filePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _pdfLoadingFlags[filePath] == true) {
            return _buildLoadingIcon();
          } else if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: Image.memory(
                snapshot.data!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            );
          } else {
            return _buildErrorIcon();
          }
        },
      );
    } else if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
      if (_docxPreviewCache.containsKey(filePath) && _docxPreviewCache[filePath] != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Image.memory(
            _docxPreviewCache[filePath]!,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      }

      return FutureBuilder<Uint8List?>(
        future: generateDocxPreview(filePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _docxLoadingFlags[filePath] == true) {
            return _buildLoadingIcon();
          } else if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: Image.memory(
                snapshot.data!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            );
          } else {
            return _buildErrorIcon();
          }
        },
      );
    } else {
      return _buildErrorIcon();
    }
  }

  Widget _buildLoadingIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: const Icon(Icons.hourglass_empty, color: Colors.grey, size: 20),
    );
  }

  Widget _buildErrorIcon() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6.0),
      ),
      child: const Icon(Icons.error_outline, color: Colors.grey, size: 20),
    );
  }
}
