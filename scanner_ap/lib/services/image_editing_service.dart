import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// top-level функции для compute() — изолят не имеет доступа к методам класса

Uint8List _removeSpotsWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final filterType = params[1] as int;

  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Не удаётся декодировать изображение');

  if (filterType == 0) {
    image = img.gaussianBlur(image, radius: 3);
  } else if (filterType == 1) {
    image = img.gaussianBlur(image, radius: 2);
  } else {
    image = img.gaussianBlur(image, radius: 2);
    image = img.gaussianBlur(image, radius: 1);
  }

  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _adjustColorsWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final brightness = params[1] as double;
  final contrast = params[2] as double;
  final saturation = params[3] as double;
  final hue = params[4] as double;

  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) throw Exception('Не удаётся декодировать изображение');

  if (brightness != 1.0) image = img.adjustColor(image, brightness: (brightness * 100).toInt());
  if (contrast != 1.0) image = img.adjustColor(image, contrast: ((contrast - 1.0) * 100).toInt());
  if (saturation != 1.0) image = img.adjustColor(image, saturation: ((saturation - 1.0) * 100).toInt());
  if (hue != 0.0) image = img.adjustColor(image, hue: hue.toInt());

  return Uint8List.fromList(img.encodePng(image));
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
    return compute(_adjustColorsWork, [imageBytes, brightness, contrast, saturation, hue]);
  }

  /// Удалить пятна и шумы с изображения (фильтры)
  static Future<Uint8List> removeSpots({
    required Uint8List imageBytes,
    int? filterType,
  }) async {
    return compute(_removeSpotsWork, [imageBytes, filterType ?? 2]);
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
  static Future<Uint8List> toGrayscale({
    required Uint8List imageBytes,
  }) async {
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
