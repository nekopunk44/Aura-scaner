import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_core/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Auto-crops a passport page to its outer edges and rectifies perspective.
///
/// The pipeline mirrors the ID-card flow:
/// - ML Kit subject segmentation isolates the foreground page from background
/// - OpenCV finds the best rectangular contour
/// - Perspective is rectified with warpPerspective
///
/// If confidence is low, the original file is returned unchanged.
class PassportScanner {
  static const int _procWidth = 800;
  static const double _minAreaRatio = 0.05;
  static const double _maxAreaRatio = 0.99;
  // Порог мягче, чем раньше (0.70): рука, держащая страницу, «портит»
  // прямоугольность блоба сегментации, и обрезка отваливалась целиком.
  static const double _minRectangularity = 0.64;
  static const double _minAspectRatio = 1.10;
  static const double _maxAspectRatio = 2.00;

  static Future<File> autoCrop(File input) async {
    SubjectSegmenter? segmenter;
    cv.Mat? src, small, maskMat, kernel, closed, warped, transform;
    cv.VecPoint? srcQuad, dstQuad;
    File? tempSmall;

    try {
      final bytes = await input.readAsBytes();
      src = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return input;

      final fullWidth = src.cols;
      final fullHeight = src.rows;
      if (fullWidth < 100 || fullHeight < 100) return input;

      final scale = fullWidth / _procWidth;
      final procHeight = (fullHeight / scale).round();

      small = cv.resize(src, (_procWidth, procHeight));
      final (encOk, smallJpg) = cv.imencode('.jpg', small);
      if (!encOk) return input;

      final dir = await getTemporaryDirectory();
      tempSmall = File(
        '${dir.path}/passport_seg_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempSmall.writeAsBytes(smallJpg);

      segmenter = SubjectSegmenter(
        options: SubjectSegmenterOptions(
          enableForegroundBitmap: false,
          enableForegroundConfidenceMask: true,
          enableMultipleSubjects: SubjectResultOptions(
            enableConfidenceMask: false,
            enableSubjectBitmap: false,
          ),
        ),
      );

      final result = await segmenter.processImage(
        InputImage.fromFilePath(tempSmall.path),
      );
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) {
        debugPrint('PassportScanner: empty mask, fallback to source');
        return input;
      }
      if (mask.length != _procWidth * procHeight) {
        debugPrint(
          'PassportScanner: unexpected mask size ${mask.length}, '
          'expected ${_procWidth * procHeight}',
        );
        return input;
      }

      final bin = List<int>.generate(
        mask.length,
        (i) => mask[i] > 0.5 ? 255 : 0,
      );
      maskMat = cv.Mat.fromList(
        procHeight,
        _procWidth,
        cv.MatType.CV_8UC1,
        bin,
      );
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (11, 11));
      closed = cv.morphologyEx(maskMat, cv.MORPH_CLOSE, kernel);

      final imageArea = (_procWidth * procHeight).toDouble();

      // Попытка 1 — по маске сегментации (надёжно на контрастном фоне).
      List<List<double>>? bestQuad = _bestQuadFromBinary(closed, imageArea);
      final bool maskFound = bestQuad != null;

      // Попытка 2 (фолбэк) — по краям (Canny): спасает, когда сегментация
      // склеила страницу с рукой или посчитала «объектом» что-то другое.
      bestQuad ??= _bestQuadByEdges(small, imageArea);

      debugPrint(
        'PassportScanner: маска=${maskFound ? "✓" : "✗"} '
        'края=${maskFound ? "—" : (bestQuad != null ? "✓" : "✗")}',
      );

      if (bestQuad == null) {
        debugPrint('PassportScanner: no suitable quad found, fallback');
        return input;
      }

      final points = bestQuad.map((point) {
        return [point[0] * scale, point[1] * scale];
      }).toList();
      final ordered = _orderCorners(points);

      final topWidth = _distance(ordered[0], ordered[1]);
      final bottomWidth = _distance(ordered[3], ordered[2]);
      final leftHeight = _distance(ordered[0], ordered[3]);
      final rightHeight = _distance(ordered[1], ordered[2]);

      final outWidth = math.max(topWidth, bottomWidth).round();
      final outHeight = math.max(leftHeight, rightHeight).round();
      if (outWidth < 80 || outHeight < 120) return input;

      srcQuad = cv.VecPoint.fromList(
        ordered.map((point) {
          return cv.Point(point[0].round(), point[1].round());
        }).toList(),
      );
      dstQuad = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(outWidth - 1, 0),
        cv.Point(outWidth - 1, outHeight - 1),
        cv.Point(0, outHeight - 1),
      ]);

      transform = cv.getPerspectiveTransform(srcQuad, dstQuad);
      warped = cv.warpPerspective(src, transform, (outWidth, outHeight));

      final (warpOk, encoded) = cv.imencode('.jpg', warped);
      if (!warpOk) return input;

      final output = File(
        '${input.parent.path}/passportcrop_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(encoded);
      // Выровненный кроп мог оказаться целым разворотом — страница и
      // разворот почти неотличимы по аспекту. Согласуем с live-рамкой:
      // при непрерывном сгибе через центр отрезаем страницу данных.
      return _splitSpreadIfNeeded(output);
    } catch (error) {
      debugPrint('PassportScanner: $error');
      return input;
    } finally {
      await segmenter?.close();
      src?.dispose();
      small?.dispose();
      maskMat?.dispose();
      kernel?.dispose();
      closed?.dispose();
      warped?.dispose();
      transform?.dispose();
      srcQuad?.dispose();
      dstQuad?.dispose();
      if (tempSmall != null) {
        try {
          await tempSmall.delete();
        } catch (_) {}
      }
    }
  }

  /// Лучший четырёхугольник из контуров по гейтам (площадь, прямоугольность,
  /// соотношение сторон). Координаты — в пикселях уменьшенной копии.
  static List<List<double>>? _bestQuad(
    cv.VecVecPoint contours,
    double imageArea,
  ) {
    List<List<double>>? bestQuad;
    var bestArea = 0.0;
    for (final contour in contours) {
      final area = cv.contourArea(contour);
      if (area < imageArea * _minAreaRatio ||
          area > imageArea * _maxAreaRatio) {
        continue;
      }
      final rect = cv.minAreaRect(contour);
      final width = rect.size.width;
      final height = rect.size.height;
      final rectArea = width * height;
      if (rectArea >= 1) {
        final rectangularity = area / rectArea;
        final longer = math.max(width, height);
        final shorter = math.min(width, height);
        final ratio = shorter < 1 ? 0.0 : longer / shorter;
        if (rectangularity >= _minRectangularity &&
            ratio >= _minAspectRatio &&
            ratio <= _maxAspectRatio &&
            area > bestArea) {
          final corners = rect.points;
          bestArea = area;
          bestQuad = corners
              .map((p) => [p.x.toDouble(), p.y.toDouble()])
              .toList();
          corners.dispose();
        }
      }
      rect.dispose();
    }
    return bestQuad;
  }

  /// Поиск страницы по бинарной маске (сегментация).
  static List<List<double>>? _bestQuadFromBinary(
    cv.Mat binary,
    double imageArea,
  ) {
    final (contours, hierarchy) = cv.findContours(
      binary,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    hierarchy.dispose();
    final quad = _bestQuad(contours, imageArea);
    contours.dispose();
    return quad;
  }

  /// Поиск страницы по краям (Canny) — фолбэк, когда сегментация склеила
  /// страницу с рукой или выбрала «объектом» что-то другое.
  static List<List<double>>? _bestQuadByEdges(cv.Mat small, double imageArea) {
    cv.Mat? gray, blurred, edges, kernel, closed;
    cv.VecVecPoint? contours;
    try {
      gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);
      // Пороги ниже, чем у DocumentScanner: страница паспорта на светлом
      // полу даёт слабые края (бел-на-светлом).
      edges = cv.canny(blurred, 40.0, 130.0);
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
      closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
      final (cnts, hierarchy) = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      hierarchy.dispose();
      contours = cnts;
      return _bestQuad(cnts, imageArea);
    } finally {
      gray?.dispose();
      blurred?.dispose();
      edges?.dispose();
      kernel?.dispose();
      closed?.dispose();
      contours?.dispose();
    }
  }

  static List<List<double>> _orderCorners(List<List<double>> points) {
    List<double> topLeft = points[0];
    List<double> topRight = points[0];
    List<double> bottomRight = points[0];
    List<double> bottomLeft = points[0];
    var minSum = double.infinity;
    var maxSum = -double.infinity;
    var minDiff = double.infinity;
    var maxDiff = -double.infinity;

    for (final point in points) {
      final sum = point[0] + point[1];
      final diff = point[1] - point[0];
      if (sum < minSum) {
        minSum = sum;
        topLeft = point;
      }
      if (sum > maxSum) {
        maxSum = sum;
        bottomRight = point;
      }
      if (diff < minDiff) {
        minDiff = diff;
        topRight = point;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        bottomLeft = point;
      }
    }

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  static double _distance(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Кроп по нормализованному прямоугольнику live-рамки (0..1 в портретной
  /// ориентации кадра). Последний рубеж, когда ни сегментация, ни поиск по
  /// краям не нашли страницу на снимке: лучше кадр по рамке, чем весь фон.
  static Future<File> cropByNormalizedRect(File input, Rect bounds) async {
    // Декод/кроп/энкод многомегапиксельного JPEG — тяжёлая CPU-работа:
    // выполняется в фоновом изоляте, чтобы интерфейс не замирал.
    final resultPath = await compute(_cropByRectWorker, (
      input.path,
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ));
    return resultPath == null ? input : File(resultPath);
  }

  /// Выровненный кроп может оказаться целым разворотом: страница (1.42) и
  /// разворот (1.41) неотличимы по аспекту. Если через центр кропа проходит
  /// непрерывный сгиб (по любой из осей), отрезаем страницу данных —
  /// половину с большей плотностью деталей (портрет + MRZ «шумнее»
  /// соседней визовой страницы). Синхронизировано с live-рамкой камеры.
  static Future<File> _splitSpreadIfNeeded(File cropped) async {
    // Анализ сгиба и перекодирование — в фоновом изоляте.
    final resultPath = await compute(_splitSpreadWorker, cropped.path);
    return resultPath == null ? cropped : File(resultPath);
  }
}

/// Фоновая часть [PassportScanner.cropByNormalizedRect] (изолят).
String? _cropByRectWorker((String, double, double, double, double) args) {
  final (path, boundsLeft, boundsTop, boundsRight, boundsBottom) = args;
  try {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final baked = img.bakeOrientation(decoded);

    const margin = 0.04; // небольшой запас вокруг рамки
    final left = ((boundsLeft - margin) * baked.width).round().clamp(
      0,
      baked.width - 2,
    );
    final top = ((boundsTop - margin) * baked.height).round().clamp(
      0,
      baked.height - 2,
    );
    final right = ((boundsRight + margin) * baked.width).round().clamp(
      left + 1,
      baked.width,
    );
    final bottom = ((boundsBottom + margin) * baked.height).round().clamp(
      top + 1,
      baked.height,
    );
    if (right - left < 80 || bottom - top < 80) return null;

    final cropped = img.copyCrop(
      baked,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    final out = File(
      '${File(path).parent.path}/passportframe_'
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    out.writeAsBytesSync(img.encodeJpg(cropped, quality: 94));
    return out.path;
  } catch (error) {
    debugPrint('PassportScanner: ошибка кропа по рамке: $error');
    return null;
  }
}

/// Фоновая часть [PassportScanner._splitSpreadIfNeeded] (изолят).
String? _splitSpreadWorker(String croppedPath) {
  try {
    final bytes = File(croppedPath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    const analysisWidth = 360;
    final small = img.grayscale(img.copyResize(decoded, width: analysisWidth));
    final w = small.width;
    final h = small.height;
    final scale = decoded.width / w; // ресайз пропорциональный: общий у осей

    int lumaAt(int x, int y) =>
        small.getPixel(x.clamp(0, w - 1), y.clamp(0, h - 1)).r.toInt();

    // Лучшая непрерывная линия в центральной полосе (42–58%) вдоль оси.
    ({int pos, double score})? bestFold({required bool verticalLine}) {
      final primary = verticalLine ? w : h;
      final secondary = verticalLine ? h : w;
      final from = (primary * 0.42).round();
      final to = (primary * 0.58).round();
      final s0 = (secondary * 0.08).round();
      final s1 = (secondary * 0.92).round();
      ({int pos, double score})? best;
      for (int p = from; p <= to; p += 2) {
        var strong = 0;
        var run = 0;
        var longestRun = 0;
        var gap = 0;
        var samples = 0;
        for (int s = s0; s <= s1; s += 2) {
          final a = verticalLine ? lumaAt(p - 2, s) : lumaAt(s, p - 2);
          final b = verticalLine ? lumaAt(p + 2, s) : lumaAt(s, p + 2);
          // Перепад между бледными страницами мал — порог низкий.
          if ((b - a).abs() >= 5) {
            strong++;
            run++;
            gap = 0;
            longestRun = math.max(longestRun, run);
          } else if (run > 0 && gap < 2) {
            run++;
            gap++;
          } else {
            run = 0;
            gap = 0;
          }
          samples++;
        }
        if (samples == 0) continue;
        final coverage = strong / samples;
        final runRatio = longestRun / samples;
        if (coverage < 0.30 || runRatio < 0.25) continue;
        final score = coverage * 0.65 + runRatio * 0.35;
        if (best == null || score > best.score) {
          best = (pos: p, score: score);
        }
      }
      return best;
    }

    final vertical = bestFold(verticalLine: true);
    final horizontal = bestFold(verticalLine: false);
    final useVertical =
        vertical != null &&
        (horizontal == null || vertical.score >= horizontal.score);
    final fold = useVertical ? vertical : horizontal;
    if (fold == null) return null;

    double density(int x0, int y0, int x1, int y1) {
      final xa = x0 + ((x1 - x0) * 0.08).round();
      final xb = x1 - ((x1 - x0) * 0.08).round();
      final ya = y0 + ((y1 - y0) * 0.10).round();
      final yb = y1 - ((y1 - y0) * 0.10).round();
      if (xb - xa < 8 || yb - ya < 8) return 0;
      var sum = 0.0;
      var count = 0;
      for (int y = ya; y <= yb; y += 3) {
        for (int x = xa; x <= xb; x += 3) {
          sum +=
              (lumaAt(x + 2, y) - lumaAt(x - 2, y)).abs() +
              (lumaAt(x, y + 2) - lumaAt(x, y - 2)).abs();
          count++;
        }
      }
      return count == 0 ? 0 : sum / count;
    }

    // Скор MRZ-полосы: строки OCR-B дают плотную равномерную полосу
    // сильных перепадов почти на всю длину строки. Ориентация текста на
    // кропе неизвестна — проверяем обе и берём максимум.
    double mrzScore(int x0, int y0, int x1, int y1) {
      final xa = x0 + ((x1 - x0) * 0.06).round();
      final xb = x1 - ((x1 - x0) * 0.06).round();
      final ya = y0 + ((y1 - y0) * 0.06).round();
      final yb = y1 - ((y1 - y0) * 0.06).round();
      if (xb - xa < 16 || yb - ya < 16) return 0;
      const threshold = 16;

      double lineCoverage(int pos, {required bool verticalText}) {
        var strong = 0;
        var samples = 0;
        if (verticalText) {
          for (int y = ya; y <= yb; y += 2) {
            if ((lumaAt(pos, y + 2) - lumaAt(pos, y - 2)).abs() >= threshold) {
              strong++;
            }
            samples++;
          }
        } else {
          for (int x = xa; x <= xb; x += 2) {
            if ((lumaAt(x + 2, pos) - lumaAt(x - 2, pos)).abs() >= threshold) {
              strong++;
            }
            samples++;
          }
        }
        return samples == 0 ? 0 : strong / samples;
      }

      var best = 0.0;
      for (int y = ya; y + 4 <= yb; y += 2) {
        final coverage =
            (lineCoverage(y, verticalText: false) +
                lineCoverage(y + 2, verticalText: false) +
                lineCoverage(y + 4, verticalText: false)) /
            3;
        if (coverage > best) best = coverage;
      }
      for (int x = xa; x + 4 <= xb; x += 2) {
        final coverage =
            (lineCoverage(x, verticalText: true) +
                lineCoverage(x + 2, verticalText: true) +
                lineCoverage(x + 4, verticalText: true)) /
            3;
        if (coverage > best) best = coverage;
      }
      return best;
    }

    // Выбор половины: сперва MRZ (есть только на странице данных),
    // при неубедительности — сравнение плотности деталей.
    bool firstHalfIsDataPage(
      int ax0,
      int ay0,
      int ax1,
      int ay1,
      int bx0,
      int by0,
      int bx1,
      int by1,
    ) {
      final mrzA = mrzScore(ax0, ay0, ax1, ay1);
      final mrzB = mrzScore(bx0, by0, bx1, by1);
      const mrzMin = 0.40;
      if (mrzA >= mrzMin && mrzA >= mrzB * 1.25) return true;
      if (mrzB >= mrzMin && mrzB >= mrzA * 1.25) return false;
      return density(ax0, ay0, ax1, ay1) > density(bx0, by0, bx1, by1);
    }

    // Заход за сгиб на ~1.5%, чтобы не оставлять тёмную полосу шва.
    final overlap = (useVertical ? w : h) * 0.015;
    late final img.Image page;
    if (useVertical) {
      final firstDenser = firstHalfIsDataPage(
        0,
        0,
        fold.pos,
        h,
        fold.pos,
        0,
        w,
        h,
      );
      final cut = ((fold.pos + (firstDenser ? overlap : -overlap)) * scale)
          .round()
          .clamp(1, decoded.width - 1);
      page = firstDenser
          ? img.copyCrop(
              decoded,
              x: 0,
              y: 0,
              width: cut,
              height: decoded.height,
            )
          : img.copyCrop(
              decoded,
              x: cut,
              y: 0,
              width: decoded.width - cut,
              height: decoded.height,
            );
    } else {
      final firstDenser = firstHalfIsDataPage(
        0,
        0,
        w,
        fold.pos,
        0,
        fold.pos,
        w,
        h,
      );
      final cut = ((fold.pos + (firstDenser ? overlap : -overlap)) * scale)
          .round()
          .clamp(1, decoded.height - 1);
      page = firstDenser
          ? img.copyCrop(decoded, x: 0, y: 0, width: decoded.width, height: cut)
          : img.copyCrop(
              decoded,
              x: 0,
              y: cut,
              width: decoded.width,
              height: decoded.height - cut,
            );
    }

    final out = File(
      '${File(croppedPath).parent.path}/passportpage_'
      '${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    out.writeAsBytesSync(img.encodeJpg(page, quality: 94));
    return out.path;
  } catch (error) {
    debugPrint('PassportScanner: ошибка резки разворота: $error');
    return null;
  }
}
