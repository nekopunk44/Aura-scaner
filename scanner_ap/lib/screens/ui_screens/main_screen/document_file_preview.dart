import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'document_utils.dart';

/// Превью файлов для списка документов: картинки читаются с диска,
/// PDF/DOCX рендерятся через [DocumentUtils], любой текстовый формат
/// рисуется как мини-страница с первыми строками текста.
///
/// Future-кэш ограничен по размеру (LRU), чтобы длинный список не держал
/// сотни футур в памяти. Кэш публичный: экран инвалидирует записи при
/// удалении/переименовании файла.
mixin DocumentFilePreview<T extends StatefulWidget>
    on State<T>, DocumentUtils<T> {
  static const int _kMaxPreviewFutures = 80;

  final LinkedHashMap<String, Future<Uint8List?>> previewFutures =
      LinkedHashMap<String, Future<Uint8List?>>();

  Future<Uint8List?> _previewFutureFor(String filePath) {
    final existing = previewFutures.remove(filePath);
    if (existing != null) {
      previewFutures[filePath] = existing;
      return existing;
    }
    final future = loadPreviewFuture(filePath);
    previewFutures[filePath] = future;
    while (previewFutures.length > _kMaxPreviewFutures) {
      previewFutures.remove(previewFutures.keys.first);
    }
    return future;
  }

  Future<Uint8List?> loadPreviewFuture(String filePath) async {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    try {
      if (fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.png') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.bmp')) {
        return await File(filePath).readAsBytes();
      } else if (fileName.endsWith('.pdf')) {
        return await generatePdfPreview(filePath);
      } else if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
        return await generateDocxPreview(filePath);
      }
      // Любой текстовый формат (txt, md, csv, json, log, yaml, xml...)
      // рисуем как text-preview — пользователь сразу видит первые строки
      // вместо безликой иконки.
      try {
        final content = await File(filePath).readAsString();
        return await _createTextPreview(content);
      } catch (_) {
        return null;
      }
    } catch (e) {
      debugPrint('Preview error for $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _createTextPreview(String content) async {
    try {
      // Берём первые ~12 не пустых строк — это даёт несколько заметных
      // строк текста в превью, а не 100 склеенных символов в одну линию.
      final lines = content
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(12)
          .toList();
      final preview = lines.join('\n');
      return await _textToImage(preview);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _textToImage(String text) async {
    const double w = 220;
    const double h = 220;
    const double pad = 14;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
    // Светлая страница с тёмным текстом — выглядит как настоящий
    // документ, а не «тёмная плашка с цифрами».
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFAFCFF),
    );
    // Лента-акцент сверху — чтобы превью читалось как «документ».
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, 6),
      Paint()..color = const Color(0xFF2CA5E0),
    );
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 10,
        textDirection: TextDirection.ltr,
        maxLines: 14,
        ellipsis: '…',
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFF1A1A2E),
        fontSize: 10,
        height: 1.35,
      ))
      ..addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: w - pad * 2));
    canvas.drawParagraph(paragraph, const Offset(pad, pad + 6));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Widget buildFilePreview(String filePath, bool isDark, {double size = 52}) {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    final future = _previewFutureFor(filePath);

    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _previewShimmer(isDark, size: size);
        }

        final previewBytes = snapshot.data;
        if (previewBytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              height: size,
              child: Image.memory(
                previewBytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    buildFileIcon(fileName, isDark, size: size),
              ),
            ),
          );
        }

        return buildFileIcon(fileName, isDark, size: size);
      },
    );
  }

  Widget _previewShimmer(bool isDark, {double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: isDark ? Colors.white24 : const Color(0xFFCCD3E0),
          ),
        ),
      ),
    );
  }

  Widget buildFileIcon(String fileName, bool isDark, {double size = 52}) {
    final (color, icon) = _fileStyle(fileName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.25), width: 1),
      ),
      child: Center(child: Icon(icon, color: color, size: size * 0.42)),
    );
  }

  (Color, IconData) _fileStyle(String fileName) {
    if (fileName.endsWith('.pdf')) {
      return (const Color(0xFFEF5350), Icons.picture_as_pdf_outlined);
    }
    if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
      return (const Color(0xFF2CA5E0), Icons.description_outlined);
    }
    if (fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png')) {
      return (const Color(0xFF26C060), Icons.image_outlined);
    }
    if (fileName.endsWith('.txt')) {
      return (const Color(0xFF9E9E9E), Icons.text_fields_rounded);
    }
    return (const Color(0xFFFF9800), Icons.insert_drive_file_outlined);
  }
}
