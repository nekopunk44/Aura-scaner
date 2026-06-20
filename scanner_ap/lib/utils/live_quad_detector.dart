import 'dart:ui';

import 'package:opencv_core/opencv.dart' as cv;

/// Живой поиск четырёхугольника фотографии для overlay-рамки (CamScanner-стиль).
///
/// Вход — портретный luma-кадр (как в превью): `gray` длиной width*height,
/// значения 0..255. Возвращает 4 угла, упорядоченные [tl, tr, br, bl], в
/// НОРМАЛИЗОВАННЫХ координатах 0..1 относительно полного кадра сенсора, либо
/// null, если уверенного прямоугольника нет.
///
/// Лёгкая операция (Canny + контуры на уменьшенном кадре) — рассчитана на
/// вызов из стрима камеры на каждом N-м кадре. Это лишь визуальная подсказка;
/// финальная обрезка делается отдельно (DocumentScanner) уже по снимку.
List<Offset>? detectPhotoQuad(List<int> gray, int width, int height) {
  cv.Mat? mat, blurred, edges, kernel, dilated;
  cv.VecVecPoint? contours;
  try {
    mat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, gray);
    blurred = cv.gaussianBlur(mat, (5, 5), 0);
    edges = cv.canny(blurred, 50.0, 150.0);
    // Замыкаем разрывы краёв, чтобы контур фото получился цельным.
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    dilated = cv.dilate(edges, kernel);

    final (cnts, hierarchy) =
        cv.findContours(dilated, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    hierarchy.dispose();
    contours = cnts;

    final double imgArea = (width * height).toDouble();
    List<List<double>>? best;
    double bestArea = 0;

    for (final c in contours) {
      final double area = cv.contourArea(c);
      // Фото должно занимать заметную часть кадра, но не весь экран целиком.
      if (area < imgArea * 0.10 || area > imgArea * 0.985) continue;

      List<List<double>>? quad;
      double rectangularity = 1.0;

      // 1) Честный 4-угольник (с перспективой) — если контур к нему сводится.
      final double peri = cv.arcLength(c, true);
      final approx = cv.approxPolyDP(c, 0.02 * peri, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        quad = approx.map((p) => [p.x.toDouble(), p.y.toDouble()]).toList();
      }
      approx.dispose();

      // 2) Фолбэк — повёрнутый прямоугольник (стабильнее при шумных краях).
      if (quad == null) {
        final rect = cv.minAreaRect(c);
        final double rw = rect.size.width;
        final double rh = rect.size.height;
        final double rectArea = rw * rh;
        if (rectArea >= 1) {
          rectangularity = area / rectArea;
          final corners = rect.points;
          quad = corners.map((p) => [p.x.toDouble(), p.y.toDouble()]).toList();
          corners.dispose();
        }
        rect.dispose();
      }

      if (quad == null) continue;
      if (rectangularity < 0.6) continue; // отбрасываем «рваные» формы
      if (area <= bestArea) continue;
      bestArea = area;
      best = quad;
    }

    if (best == null) return null;
    final ordered = _orderCorners(best);
    return ordered
        .map((p) => Offset(p[0] / width, p[1] / height))
        .toList(growable: false);
  } catch (_) {
    return null;
  } finally {
    mat?.dispose();
    blurred?.dispose();
    edges?.dispose();
    kernel?.dispose();
    dilated?.dispose();
    contours?.dispose();
  }
}

/// Упорядочивает 4 точки как [tl, tr, br, bl] по суммам/разностям координат.
List<List<double>> _orderCorners(List<List<double>> pts) {
  List<double> tl = pts[0], br = pts[0], tr = pts[0], bl = pts[0];
  double minSum = double.infinity, maxSum = -double.infinity;
  double minDiff = double.infinity, maxDiff = -double.infinity;
  for (final p in pts) {
    final double s = p[0] + p[1];
    final double d = p[1] - p[0];
    if (s < minSum) {
      minSum = s;
      tl = p;
    }
    if (s > maxSum) {
      maxSum = s;
      br = p;
    }
    if (d < minDiff) {
      minDiff = d;
      tr = p;
    }
    if (d > maxDiff) {
      maxDiff = d;
      bl = p;
    }
  }
  return [tl, tr, br, bl];
}
