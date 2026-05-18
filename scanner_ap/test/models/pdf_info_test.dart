import 'package:flutter_test/flutter_test.dart';

import 'package:scanner_ap/services/pdf_service.dart';

void main() {
  group('PdfInfo', () {
    test('fileSizeMB считает мегабайты корректно', () {
      final info = PdfInfo(
        pageCount: 3,
        fileSizeBytes: 1024 * 1024,
        fileName: 'test.pdf',
      );
      expect(info.fileSizeMB, '1.00');
    });

    test('fileSizeMB для 512 KB равен 0.50', () {
      final info = PdfInfo(
        pageCount: 1,
        fileSizeBytes: 512 * 1024,
        fileName: 'small.pdf',
      );
      expect(info.fileSizeMB, '0.50');
    });

    test('fileSizeMB для 0 байт равен 0.00', () {
      final info = PdfInfo(
        pageCount: 0,
        fileSizeBytes: 0,
        fileName: 'empty.pdf',
      );
      expect(info.fileSizeMB, '0.00');
    });

    test('pageCount и fileName сохраняются', () {
      final info = PdfInfo(
        pageCount: 7,
        fileSizeBytes: 2048,
        fileName: 'document.pdf',
      );
      expect(info.pageCount, 7);
      expect(info.fileName, 'document.pdf');
    });
  });
}
