import 'dart:math' as math;
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// top-level функции для compute() — изолят не имеет доступа к методам класса

Uint8List _removeSpotsWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final filterType = params[1] as int;

  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Не удаётся декодировать изображение');

  // Подстраховка: если изображение всё ещё крупное (>1600px по длинной стороне),
  // даунскейлим перед свёрткой — иначе gaussianBlur на 12MP занимает >10с.
  const int maxSide = 1600;
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxSide);
    } else {
      image = img.copyResize(image, height: maxSide);
    }
  }

  if (filterType == 0) {
    image = img.gaussianBlur(image, radius: 3);
  } else if (filterType == 1) {
    image = img.gaussianBlur(image, radius: 2);
  } else {
    image = img.gaussianBlur(image, radius: 2);
    image = img.gaussianBlur(image, radius: 1);
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

Uint8List _adjustColorsWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final brightness = params[1] as double;
  final contrast = params[2] as double;
  final saturation = params[3] as double;
  final hue = params[4] as double;

  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Не удаётся декодировать изображение');

  if (brightness != 1.0) {
    image = img.adjustColor(image, brightness: (brightness * 100).toInt());
  }
  if (contrast != 1.0) {
    image = img.adjustColor(image, contrast: ((contrast - 1.0) * 100).toInt());
  }
  if (saturation != 1.0) {
    image = img.adjustColor(
      image,
      saturation: ((saturation - 1.0) * 100).toInt(),
    );
  }
  if (hue != 0.0) {
    image = img.adjustColor(image, hue: hue.toInt());
  }

  return Uint8List.fromList(img.encodePng(image));
}

class _SpotCandidate {
  const _SpotCandidate({required this.x, required this.y, required this.score});

  final double x;
  final double y;
  final double score;
}

/// Сервис для обработки и редактирования изображений
class ImageEditingService {
  /// Изменить цвет документа (яркость, контраст, насыщенность, оттенок)
  static Future<Uint8List> adjustColors({
    required Uint8List imageBytes,
    double brightness = 1.0,
    double contrast = 1.0,
    double saturation = 1.0,
    double hue = 0.0,
  }) async {
    return compute(_adjustColorsWork, [
      imageBytes,
      brightness,
      contrast,
      saturation,
      hue,
    ]);
  }

  /// Удалить пятна и шумы с изображения (фильтры)
  static Future<Uint8List> removeSpots({
    required Uint8List imageBytes,
    int? filterType,
  }) async {
    return compute(_removeSpotsWork, [imageBytes, filterType ?? 2]);
  }

  static Future<List<Offset>> detectSpotMarkers({
    required Uint8List imageBytes,
    int maxSpots = 12,
  }) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('Не удаётся декодировать изображение');
    }

    const int maxSide = 1200;
    final longest = math.max(image.width, image.height);
    if (longest > maxSide) {
      if (image.width >= image.height) {
        image = img.copyResize(image, width: maxSide);
      } else {
        image = img.copyResize(image, height: maxSide);
      }
    }

    final candidates = <_SpotCandidate>[];
    const step = 8;
    const sampleRadius = 4;
    const minDistance = 28.0;

    double luminance(int x, int y) {
      final pixel = image!.getPixelSafe(x, y);
      return pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
    }

    for (int y = sampleRadius; y < image.height - sampleRadius; y += step) {
      for (int x = sampleRadius; x < image.width - sampleRadius; x += step) {
        final center = luminance(x, y);
        final localMean =
            (center +
                luminance(x - sampleRadius, y) +
                luminance(x + sampleRadius, y) +
                luminance(x, y - sampleRadius) +
                luminance(x, y + sampleRadius)) /
            5;
        final score = localMean - center;
        if (score < 20 || center > 190) {
          continue;
        }

        final candidate = _SpotCandidate(
          x: x / image.width,
          y: y / image.height,
          score: score,
        );

        final duplicateIndex = candidates.indexWhere((existing) {
          final dx = (existing.x - candidate.x) * image!.width;
          final dy = (existing.y - candidate.y) * image.height;
          return math.sqrt(dx * dx + dy * dy) < minDistance;
        });

        if (duplicateIndex == -1) {
          candidates.add(candidate);
        } else if (candidates[duplicateIndex].score < candidate.score) {
          candidates[duplicateIndex] = candidate;
        }
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates
        .take(maxSpots)
        .map((spot) => Offset(spot.x, spot.y))
        .toList(growable: false);
  }

  static Future<Uint8List> removeSpotAt({
    required Uint8List imageBytes,
    required Offset normalizedCenter,
    double normalizedRadius = 0.035,
  }) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      throw Exception('Не удаётся декодировать изображение');
    }

    final centerX = (normalizedCenter.dx * image.width).round().clamp(
      0,
      image.width - 1,
    );
    final centerY = (normalizedCenter.dy * image.height).round().clamp(
      0,
      image.height - 1,
    );
    final radius = (math.min(image.width, image.height) * normalizedRadius)
        .round()
        .clamp(10, 72);
    final blurRadius = math.max(2, (radius / 5).round());

    final left = math.max(0, centerX - radius * 2);
    final top = math.max(0, centerY - radius * 2);
    final right = math.min(image.width, centerX + radius * 2);
    final bottom = math.min(image.height, centerY + radius * 2);

    final patch = img.copyCrop(
      image,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    final blurredPatch = img.gaussianBlur(
      img.Image.from(patch),
      radius: blurRadius,
    );

    for (int y = 0; y < patch.height; y++) {
      for (int x = 0; x < patch.width; x++) {
        final dx = x - (centerX - left);
        final dy = y - (centerY - top);
        final distance = math.sqrt((dx * dx + dy * dy).toDouble());
        if (distance > radius) {
          continue;
        }

        final strength = math.pow(1 - (distance / radius), 2).toDouble() * 0.92;
        final original = patch.getPixelSafe(x, y);
        final blurred = blurredPatch.getPixelSafe(x, y);
        final r = (original.r * (1 - strength) + blurred.r * strength).round();
        final g = (original.g * (1 - strength) + blurred.g * strength).round();
        final b = (original.b * (1 - strength) + blurred.b * strength).round();

        image.setPixelRgba(left + x, top + y, r, g, b, original.a);
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  }

  /// Повысить резкость изображения
  static Future<Uint8List> sharpen({
    required Uint8List imageBytes,
    double amount = 1.0, // 0.0-2.0
  }) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Не удаётся декодировать изображение');

    // Используем встроенный фильтр резкости
    // Если его нет, применим контрастность как альтернативу
    image = img.adjustColor(image, contrast: (amount * 30).toInt());

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Преобразовать в черно-белое
  static Future<Uint8List> toGrayscale({required Uint8List imageBytes}) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Не удаётся декодировать изображение');

    image = img.grayscale(image);

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Преобразовать в черно-белое (для сканов документов)
  static Future<Uint8List> toBlackAndWhite({
    required Uint8List imageBytes,
    int threshold = 128, // 0-255, яркость порога
  }) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Не удаётся декодировать изображение');

    // Сначала в оттенки серого
    image = img.grayscale(image);

    // Затем применим пороговое преобразование вручную
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixelSafe(x, y);
        final gray = (pixel.r + pixel.g + pixel.b) ~/ 3;
        final newColor = gray > threshold ? 255 : 0;
        image.setPixelRgba(x, y, newColor, newColor, newColor, 255);
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Изменить размер изображения
  static Future<Uint8List> resize({
    required Uint8List imageBytes,
    required int width,
    required int height,
  }) async {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Не удаётся декодировать изображение');

    image = img.copyResize(image, width: width, height: height);

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Применить несколько фильтров сразу
  static Future<Uint8List> applyFilters({
    required Uint8List imageBytes,
    double brightness = 1.0,
    double contrast = 1.0,
    double saturation = 1.0,
    double hue = 0.0,
    bool sharpenImage = false,
    bool removeNoise = false,
  }) async {
    Uint8List result = imageBytes;

    // Обработка шума
    if (removeNoise) {
      result = await removeSpots(imageBytes: result);
    }

    // Цветокоррекция
    result = await adjustColors(
      imageBytes: result,
      brightness: brightness,
      contrast: contrast,
      saturation: saturation,
      hue: hue,
    );

    // Резкость
    if (sharpenImage) {
      result = await sharpen(imageBytes: result, amount: 1.0);
    }

    return result;
  }
}
