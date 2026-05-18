import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;

/// Сервис для работы с PDF документами
class PdfService {
  /// Сжать PDF документ (уменьшить размер)
  static Future<Uint8List> compressPdf({
    required String pdfPath,
    double qualityFactor = 0.7, // 0.0-1.0, где 1.0 = максимальное качество
  }) async {
    try {
      final pdfDoc = await PdfDocument.openFile(pdfPath);
      final doc = pw.Document();

      final pdfWidth = PdfPageFormat.a4.width;
      final pdfHeight = PdfPageFormat.a4.height;

      // Определяем размер для рендеринга на основе качества
      final renderWidth = (1024 * qualityFactor).clamp(512.0, 2048.0);
      final renderHeight = (1024 * qualityFactor).clamp(512.0, 2048.0);

      for (int i = 0; i < pdfDoc.pages.length; i++) {
        final page = pdfDoc.pages[i];

        final pdfImage = await page.render(
          fullWidth: renderWidth,
          fullHeight: renderHeight,
        );

        if (pdfImage != null) {
          try {
            // Конвертируем в изображение и обратно в PDF с меньшим качеством
            final imgImage = img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              order: img.ChannelOrder.bgra,
            );

            // Сжимаем с потерей качества для уменьшения размера
            final jpegQuality = (90 * qualityFactor).toInt().clamp(40, 90);
            final jpegBytes = img.encodeJpg(imgImage, quality: jpegQuality);

            doc.addPage(pw.Page(
              pageFormat: PdfPageFormat(pdfWidth, pdfHeight),
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Image(
                pw.MemoryImage(jpegBytes),
                fit: pw.BoxFit.fill,
              ),
            ));
          } finally {
            pdfImage.dispose();
          }
        }
      }

      await pdfDoc.dispose();
      return await doc.save();
    } catch (e) {
      throw Exception('Ошибка сжатия PDF: $e');
    }
  }

  /// Извлечь определённые страницы из PDF
  static Future<Uint8List> extractPages({
    required String pdfPath,
    required List<int> pageNumbers, // 1-based индексы (1, 2, 3...)
  }) async {
    try {
      final pdfDoc = await PdfDocument.openFile(pdfPath);

      // Фильтруем валидные номера страниц
      final validPages = pageNumbers
          .where((n) => n > 0 && n <= pdfDoc.pages.length)
          .map((n) => n - 1) // Конвертируем в 0-based
          .toSet()
          .toList()
          ..sort();

      if (validPages.isEmpty) {
        throw Exception('Нет валидных страниц для извлечения');
      }

      final doc = pw.Document();
      final pdfWidth = PdfPageFormat.a4.width;
      final pdfHeight = PdfPageFormat.a4.height;

      for (int idx in validPages) {
        final page = pdfDoc.pages[idx];

        final pdfImage = await page.render(
          fullWidth: 1024,
          fullHeight: 1024,
        );

        if (pdfImage != null) {
          try {
            final imgImage = img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              order: img.ChannelOrder.bgra,
            );
            final pngBytes = img.encodePng(imgImage);

            doc.addPage(pw.Page(
              pageFormat: PdfPageFormat(pdfWidth, pdfHeight),
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Image(
                pw.MemoryImage(pngBytes),
                fit: pw.BoxFit.fill,
              ),
            ));
          } finally {
            pdfImage.dispose();
          }
        }
      }

      await pdfDoc.dispose();
      return await doc.save();
    } catch (e) {
      throw Exception('Ошибка извлечения страниц: $e');
    }
  }

  /// Получить информацию о PDF
  static Future<PdfInfo> getPdfInfo(String pdfPath) async {
    try {
      final pdfDoc = await PdfDocument.openFile(pdfPath);
      final fileSize = await File(pdfPath).length();

      final info = PdfInfo(
        pageCount: pdfDoc.pages.length,
        fileSizeBytes: fileSize,
        fileName: pdfPath.split('/').last,
      );

      await pdfDoc.dispose();
      return info;
    } catch (e) {
      throw Exception('Ошибка получения информации PDF: $e');
    }
  }

  /// Слить несколько PDF в один
  static Future<Uint8List> mergePdfs({
    required List<String> pdfPaths,
  }) async {
    try {
      final doc = pw.Document();
      final pdfWidth = PdfPageFormat.a4.width;
      final pdfHeight = PdfPageFormat.a4.height;

      for (final pdfPath in pdfPaths) {
        final pdfDoc = await PdfDocument.openFile(pdfPath);

        for (int i = 0; i < pdfDoc.pages.length; i++) {
          final page = pdfDoc.pages[i];

          final pdfImage = await page.render(
            fullWidth: 1024,
            fullHeight: 1024,
          );

          if (pdfImage != null) {
            try {
              final imgImage = img.Image.fromBytes(
                width: pdfImage.width,
                height: pdfImage.height,
                bytes: pdfImage.pixels.buffer,
                order: img.ChannelOrder.bgra,
              );
              final pngBytes = img.encodePng(imgImage);

              doc.addPage(pw.Page(
                pageFormat: PdfPageFormat(pdfWidth, pdfHeight),
                margin: pw.EdgeInsets.zero,
                build: (ctx) => pw.Image(
                  pw.MemoryImage(pngBytes),
                  fit: pw.BoxFit.fill,
                ),
              ));
            } finally {
              pdfImage.dispose();
            }
          }
        }

        await pdfDoc.dispose();
      }

      return await doc.save();
    } catch (e) {
      throw Exception('Ошибка слияния PDF: $e');
    }
  }

  /// Конвертировать PDF в изображения
  static Future<List<Uint8List>> pdfToImages({
    required String pdfPath,
    int? maxPages, // если указано, берёт только первые N страниц
  }) async {
    try {
      final pdfDoc = await PdfDocument.openFile(pdfPath);
      final images = <Uint8List>[];

      int pageCount = pdfDoc.pages.length;
      if (maxPages != null && maxPages > 0) {
        pageCount = pageCount > maxPages ? maxPages : pageCount;
      }

      for (int i = 0; i < pageCount; i++) {
        final page = pdfDoc.pages[i];

        final pdfImage = await page.render(
          fullWidth: 1024,
          fullHeight: 1024,
        );

        if (pdfImage != null) {
          try {
            final imgImage = img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              order: img.ChannelOrder.bgra,
            );
            images.add(Uint8List.fromList(img.encodePng(imgImage)));
          } finally {
            pdfImage.dispose();
          }
        }
      }

      await pdfDoc.dispose();
      return images;
    } catch (e) {
      throw Exception('Ошибка конвертации PDF: $e');
    }
  }
}

/// Класс с информацией о PDF
class PdfInfo {
  final int pageCount;
  final int fileSizeBytes;
  final String fileName;

  PdfInfo({
    required this.pageCount,
    required this.fileSizeBytes,
    required this.fileName,
  });

  String get fileSizeMB => (fileSizeBytes / (1024 * 1024)).toStringAsFixed(2);
}
