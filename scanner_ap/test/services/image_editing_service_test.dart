import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:scanner_ap/services/image_editing_service.dart';

Uint8List _makeTestPng({int width = 20, int height = 20}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(180, 180, 180));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageEditingService.removeSpots', () {
    test('filterType 0 возвращает непустые байты', () async {
      final result = await ImageEditingService.removeSpots(
        imageBytes: _makeTestPng(),
        filterType: 0,
      );
      expect(result, isNotEmpty);
    });

    test('filterType 1 возвращает непустые байты', () async {
      final result = await ImageEditingService.removeSpots(
        imageBytes: _makeTestPng(),
        filterType: 1,
      );
      expect(result, isNotEmpty);
    });

    test('filterType 2 (комбинированный) возвращает непустые байты', () async {
      final result = await ImageEditingService.removeSpots(
        imageBytes: _makeTestPng(),
        filterType: 2,
      );
      expect(result, isNotEmpty);
    });

    test('результат декодируется обратно в изображение', () async {
      final result = await ImageEditingService.removeSpots(
        imageBytes: _makeTestPng(),
        filterType: 0,
      );
      final decoded = img.decodeImage(result);
      expect(decoded, isNotNull);
    });

    test('неверные байты бросают исключение', () async {
      await expectLater(
        ImageEditingService.removeSpots(
          imageBytes: Uint8List.fromList([0, 1, 2, 3]),
          filterType: 0,
        ),
        throwsA(anything),
      );
    });
  });

  group('ImageEditingService.adjustColors', () {
    test('параметры по умолчанию возвращают непустые байты', () async {
      final result = await ImageEditingService.adjustColors(
        imageBytes: _makeTestPng(),
      );
      expect(result, isNotEmpty);
    });

    test('результат сохраняет размер изображения', () async {
      final source = _makeTestPng(width: 30, height: 15);
      final result = await ImageEditingService.adjustColors(
        imageBytes: source,
        brightness: 1.2,
      );
      final decoded = img.decodeImage(result);
      expect(decoded?.width, 30);
      expect(decoded?.height, 15);
    });

    test('неверные байты бросают исключение', () async {
      await expectLater(
        ImageEditingService.adjustColors(
          imageBytes: Uint8List.fromList([9, 9, 9]),
        ),
        throwsA(anything),
      );
    });
  });

  group('ImageEditingService.toGrayscale', () {
    test('возвращает непустые байты', () async {
      final result = await ImageEditingService.toGrayscale(
        imageBytes: _makeTestPng(),
      );
      expect(result, isNotEmpty);
    });

    test('результат декодируется в изображение', () async {
      final result = await ImageEditingService.toGrayscale(
        imageBytes: _makeTestPng(),
      );
      expect(img.decodeImage(result), isNotNull);
    });
  });

  group('ImageEditingService.resize', () {
    test('меняет размер на указанный', () async {
      final result = await ImageEditingService.resize(
        imageBytes: _makeTestPng(width: 20, height: 20),
        width: 10,
        height: 5,
      );
      final decoded = img.decodeImage(result);
      expect(decoded?.width, 10);
      expect(decoded?.height, 5);
    });
  });
}
