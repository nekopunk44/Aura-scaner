import 'dart:collection';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:docx_to_text/docx_to_text.dart';

const int _kMaxCacheEntries = 60;
const double _kPdfRenderScale = 1.5;

class _LruCache<K, V> {
  _LruCache(this._maxEntries);
  final int _maxEntries;
  final LinkedHashMap<K, V> _store = LinkedHashMap<K, V>();

  bool containsKey(K key) => _store.containsKey(key);

  V? operator [](K key) {
    if (!_store.containsKey(key)) return null;
    final value = _store.remove(key) as V;
    _store[key] = value;
    return value;
  }

  void operator []=(K key, V value) {
    _store.remove(key);
    _store[key] = value;
    while (_store.length > _maxEntries) {
      _store.remove(_store.keys.first);
    }
  }

  void remove(K key) => _store.remove(key);
  void clear() => _store.clear();
}

mixin DocumentUtils<T extends StatefulWidget> on State<T> {
  final _LruCache<String, Uint8List?> _pdfPreviewCache = _LruCache(_kMaxCacheEntries);
  final _LruCache<String, Uint8List?> _docxPreviewCache = _LruCache(_kMaxCacheEntries);
  final Set<String> _pdfLoadingFlags = {};
  final Set<String> _docxLoadingFlags = {};

  void updateState() {
    if (mounted) setState(() {});
  }

  String getFileNameFromPath(String path) => path.split(Platform.pathSeparator).last.split('/').last;

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
    if (_pdfLoadingFlags.remove(oldPath)) _pdfLoadingFlags.add(newPath);
    if (_docxLoadingFlags.remove(oldPath)) _docxLoadingFlags.add(newPath);
  }

  Future<String> _extractTextFromDocxBytes(Uint8List bytes) async {
    try {
      final text = docxToText(bytes);

      String cleanText = text.replaceAll(RegExp(r'[^\w\s\p{P}А-Яа-яЁё]'), ' ');
      cleanText = cleanText.replaceAll(RegExp(r'\s+'), ' ').trim();

      final totalChars = cleanText.length;
      final alphaNumericChars = cleanText.replaceAll(RegExp(r'[^a-zA-Zа-яА-Я0-9]'), '').length;

      if (totalChars > 50 && alphaNumericChars / totalChars < 0.10) {
        return '';
      }

      return cleanText;
    } catch (e) {
      debugPrint('Критическая ошибка извлечения текста из DOCX: $e');
      return '';
    }
  }

  Future<Uint8List?> generatePdfPreview(String filePath) async {
    if (_pdfLoadingFlags.contains(filePath)) return null;
    if (_pdfPreviewCache.containsKey(filePath)) return _pdfPreviewCache[filePath];

    try {
      _pdfLoadingFlags.add(filePath);

      final document = await PdfDocument.openFile(filePath);
      final page = await document.getPage(1);

      final pageImage = await page.render(
        width: page.width * _kPdfRenderScale,
        height: page.height * _kPdfRenderScale,
        format: PdfPageImageFormat.png,
      );

      await page.close();
      await document.close();

      final result = pageImage?.bytes;
      _pdfPreviewCache[filePath] = result;
      _pdfLoadingFlags.remove(filePath);

      updateState();
      return result;
    } catch (e) {
      debugPrint('Ошибка создания превью PDF: $e');
      _pdfPreviewCache[filePath] = null;
      _pdfLoadingFlags.remove(filePath);
      return null;
    }
  }

  Future<Uint8List?> generateDocxPreview(String filePath) async {
    if (_docxLoadingFlags.contains(filePath)) return null;
    if (_docxPreviewCache.containsKey(filePath)) return _docxPreviewCache[filePath];

    try {
      _docxLoadingFlags.add(filePath);

      final file = File(filePath);
      if (!await file.exists()) {
        final errorPreview = await _createPlaceholderPreview(label: 'Файл не найден');
        _docxPreviewCache[filePath] = errorPreview;
        _docxLoadingFlags.remove(filePath);
        return errorPreview;
      }

      String realContent = '';
      try {
        final bytes = await file.readAsBytes();
        realContent = await _extractTextFromDocxBytes(bytes);
      } catch (e) {
        debugPrint('Ошибка чтения или парсинга DOCX файла $filePath: $e');
      }

      final previewImage = realContent.trim().isEmpty
          ? await _createPlaceholderPreview(label: 'DOCX')
          : await _createRealDocxPreviewImage(realContent);

      _docxPreviewCache[filePath] = previewImage;
      _docxLoadingFlags.remove(filePath);

      updateState();
      return previewImage;
    } catch (e) {
      debugPrint('Ошибка создания превью DOCX: $e');
      final errorPreview = await _createPlaceholderPreview(label: 'Ошибка');
      _docxLoadingFlags.remove(filePath);
      return errorPreview;
    }
  }

  Future<Uint8List?> _createRealDocxPreviewImage(String content) async {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(160, 220);

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white,
      );

      final lines = content
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final title = lines.isNotEmpty ? lines.first : '';
      final body = lines.length > 1 ? lines.sublist(1).join('\n') : '';

      const padding = 10.0;
      const maxBodyChars = 800;
      final trimmedBody = body.length > maxBodyChars
          ? '${body.substring(0, maxBodyChars)}…'
          : body;

      double cursorY = padding;
      if (title.isNotEmpty) {
        final titlePainter = TextPainter(
          text: TextSpan(
            text: title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        );
        titlePainter.layout(maxWidth: size.width - padding * 2);
        titlePainter.paint(canvas, Offset(padding, cursorY));
        cursorY += titlePainter.height + 4;

        canvas.drawLine(
          Offset(padding, cursorY),
          Offset(size.width - padding, cursorY),
          Paint()
            ..color = Colors.blue.shade300
            ..strokeWidth = 0.8,
        );
        cursorY += 4;
      }

      if (trimmedBody.isNotEmpty) {
        final bodyPainter = TextPainter(
          text: TextSpan(
            text: trimmedBody,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 7,
              height: 1.3,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 100,
          ellipsis: '…',
        );
        bodyPainter.layout(maxWidth: size.width - padding * 2);
        final bodyHeight = (size.height - cursorY - padding).clamp(0.0, double.infinity);
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(padding, cursorY, size.width - padding * 2, bodyHeight));
        bodyPainter.paint(canvas, Offset(padding, cursorY));
        canvas.restore();
      }

      canvas.drawRect(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        Paint()
          ..color = Colors.blue.shade400
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Ошибка создания реального превью DOCX: $e');
      return _createPlaceholderPreview(label: 'Ошибка');
    }
  }

  Future<Uint8List?> _createPlaceholderPreview({required String label}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(120, 80);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.grey.shade100,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: size.width - 8);
    painter.paint(
      canvas,
      Offset((size.width - painter.width) / 2, (size.height - painter.height) / 2),
    );

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
          errorBuilder: (context, error, stackTrace) => _buildErrorIcon(),
        ),
      );
    } else if (fileName.endsWith('.pdf')) {
      final cached = _pdfPreviewCache[filePath];
      if (cached != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Image.memory(cached, width: 40, height: 40, fit: BoxFit.cover),
        );
      }
      return FutureBuilder<Uint8List?>(
        future: generatePdfPreview(filePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _pdfLoadingFlags.contains(filePath)) {
            return _buildLoadingIcon();
          }
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: Image.memory(snapshot.data!, width: 40, height: 40, fit: BoxFit.cover),
            );
          }
          return _buildErrorIcon();
        },
      );
    } else if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
      final cached = _docxPreviewCache[filePath];
      if (cached != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: Image.memory(cached, width: 40, height: 40, fit: BoxFit.cover),
        );
      }
      return FutureBuilder<Uint8List?>(
        future: generateDocxPreview(filePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _docxLoadingFlags.contains(filePath)) {
            return _buildLoadingIcon();
          }
          if (snapshot.hasData && snapshot.data != null) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(6.0),
              child: Image.memory(snapshot.data!, width: 40, height: 40, fit: BoxFit.cover),
            );
          }
          return _buildErrorIcon();
        },
      );
    }
    return _buildErrorIcon();
  }

  Widget _buildLoadingIcon() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: const Icon(Icons.hourglass_empty, color: Colors.grey, size: 20),
      );

  Widget _buildErrorIcon() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6.0),
        ),
        child: const Icon(Icons.error_outline, color: Colors.grey, size: 20),
      );
}
