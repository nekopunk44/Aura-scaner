import 'dart:typed_data';
import 'dart:ui';

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

  group('ImageEditingService.removeSpotInSelection', () {
    test('replaces a dark defect with nearby image texture', () async {
      final source = img.Image(width: 96, height: 64);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final tone = 145 + ((x ~/ 6 + y ~/ 6).isEven ? 18 : 0);
          source.setPixelRgb(x, y, tone, tone + 8, tone + 12);
        }
      }
      for (var y = 27; y <= 37; y++) {
        for (var x = 43; x <= 53; x++) {
          source.setPixelRgb(x, y, 18, 14, 12);
        }
      }

      final result = await ImageEditingService.removeSpotInSelection(
        imageBytes: Uint8List.fromList(img.encodePng(source)),
        normalizedSelection: const Rect.fromLTRB(
          38 / 96,
          22 / 64,
          59 / 96,
          43 / 64,
        ),
      );
      final restored = img.decodeImage(result)!;
      final restoredCenter = restored.getPixel(48, 32);
      final untouchedCorner = restored.getPixel(4, 4);

      expect(restoredCenter.r, greaterThan(90));
      expect((untouchedCorner.r - source.getPixel(4, 4).r).abs(), lessThan(8));
    });

    test('keeps the original dimensions', () async {
      final result = await ImageEditingService.removeSpotInSelection(
        imageBytes: _makeTestPng(width: 80, height: 45),
        normalizedSelection: const Rect.fromLTRB(0.3, 0.3, 0.6, 0.7),
      );
      final decoded = img.decodeImage(result);

      expect(decoded?.width, 80);
      expect(decoded?.height, 45);
    });
  });

  group('ImageEditingService.removeWatermarkInSelection', () {
    test(
      'replaces all separated parts inside the selected watermark',
      () async {
        final source = img.Image(width: 120, height: 72);
        for (var y = 0; y < source.height; y++) {
          for (var x = 0; x < source.width; x++) {
            final tone = 150 + ((x ~/ 8 + y ~/ 8).isEven ? 14 : 0);
            source.setPixelRgb(x, y, tone, tone + 5, tone + 10);
          }
        }
        for (var y = 29; y <= 42; y++) {
          for (var x = 43; x <= 49; x++) {
            source.setPixelRgb(x, y, 25, 25, 25);
          }
          for (var x = 65; x <= 71; x++) {
            source.setPixelRgb(x, y, 25, 25, 25);
          }
        }

        final result = await ImageEditingService.removeWatermarkInSelection(
          imageBytes: Uint8List.fromList(img.encodePng(source)),
          normalizedSelection: const Rect.fromLTRB(
            38 / 120,
            24 / 72,
            77 / 120,
            48 / 72,
          ),
        );
        final restored = img.decodeImage(result)!;

        expect(restored.getPixel(46, 35).r, greaterThan(90));
        expect(restored.getPixel(68, 35).r, greaterThan(90));
      },
    );

    test('removes several repeated watermark regions in one pass', () async {
      final source = img.Image(width: 180, height: 110);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          final tone = 145 + ((x ~/ 9 + y ~/ 9).isEven ? 16 : 0);
          source.setPixelRgb(x, y, tone, tone + 6, tone + 11);
        }
      }
      const centers = <(int, int)>[(40, 28), (92, 55), (142, 82)];
      for (final center in centers) {
        for (var y = center.$2 - 5; y <= center.$2 + 5; y++) {
          for (var x = center.$1 - 8; x <= center.$1 + 8; x++) {
            source.setPixelRgb(x, y, 24, 24, 24);
          }
        }
      }

      final result = await ImageEditingService.removeWatermarksInSelections(
        imageBytes: Uint8List.fromList(img.encodePng(source)),
        normalizedSelections: [
          for (final center in centers)
            Rect.fromLTRB(
              (center.$1 - 11) / 180,
              (center.$2 - 8) / 110,
              (center.$1 + 12) / 180,
              (center.$2 + 9) / 110,
            ),
        ],
      );
      final restored = img.decodeImage(result)!;

      for (final center in centers) {
        expect(
          restored.getPixel(center.$1, center.$2).r,
          greaterThan(85),
          reason: 'watermark at $center should be removed',
        );
      }
    });
  });

  group('ImageEditingService.detectWatermarkRegions', () {
    test('finds a text-like watermark made of separated strokes', () async {
      final source = img.Image(width: 240, height: 140);
      img.fill(source, color: img.ColorRgb8(125, 130, 135));
      for (var letter = 0; letter < 8; letter++) {
        final left = 55 + letter * 17;
        for (var y = 54; y <= 84; y++) {
          for (var x = left; x <= left + 10; x++) {
            final isStroke = x == left || x == left + 10 || y == 54 || y == 84;
            if (isStroke) {
              source.setPixelRgb(x, y, 205, 205, 205);
            }
          }
        }
      }

      final regions = await ImageEditingService.detectWatermarkRegions(
        imageBytes: Uint8List.fromList(img.encodePng(source)),
      );

      expect(
        regions.any(
          (region) =>
              region.center.dx > 0.35 &&
              region.center.dx < 0.70 &&
              region.center.dy > 0.30 &&
              region.center.dy < 0.70 &&
              region.width > 0.35,
        ),
        isTrue,
      );
    });

    test(
      'keeps separate repeated watermark words as separate regions',
      () async {
        final source = img.Image(width: 300, height: 180);
        img.fill(source, color: img.ColorRgb8(118, 124, 130));
        const origins = <(int, int)>[(18, 18), (165, 74), (52, 132)];
        for (final origin in origins) {
          for (var letter = 0; letter < 5; letter++) {
            final left = origin.$1 + letter * 14;
            final top = origin.$2;
            for (var y = top; y <= top + 20; y++) {
              for (var x = left; x <= left + 8; x++) {
                if (x == left || x == left + 8 || y == top || y == top + 20) {
                  source.setPixelRgb(x, y, 205, 205, 205);
                }
              }
            }
          }
        }

        final regions = await ImageEditingService.detectWatermarkRegions(
          imageBytes: Uint8List.fromList(img.encodePng(source)),
        );

        expect(regions.length, greaterThanOrEqualTo(3));
      },
    );
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
