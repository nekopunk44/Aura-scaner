import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:opencv_core/opencv.dart' as cv;
import 'package:path_provider/path_provider.dart';

/// Auto-crops a paper document to page edges and rectifies perspective.
///
/// Intended for ordinary sheets in the "Документ" capture flow.
/// If detection confidence is low, returns the original file unchanged.
class DocumentScanner {
  static const int _procWidth = 800;
  static const double _minAreaRatio = 0.08;
  static const double _maxAreaRatio = 0.995;
  static const double _minRectangularity = 0.62;
  static const double _minAspectRatio = 1.15;
  static const double _maxAspectRatio = 1.95;

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
        '${dir.path}/document_seg_${DateTime.now().microsecondsSinceEpoch}.jpg',
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
        debugPrint('DocumentScanner: empty mask, fallback to source');
        return input;
      }
      if (mask.length != _procWidth * procHeight) {
        debugPrint(
          'DocumentScanner: unexpected mask size ${mask.length}, '
          'expected ${_procWidth * procHeight}',
        );
        return input;
      }

      final bin = List<int>.generate(mask.length, (i) => mask[i] > 0.5 ? 255 : 0);
      maskMat = cv.Mat.fromList(
        procHeight,
        _procWidth,
        cv.MatType.CV_8UC1,
        bin,
      );
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (13, 13));
      closed = cv.morphologyEx(maskMat, cv.MORPH_CLOSE, kernel);

      final imageArea = (_procWidth * procHeight).toDouble();

      // Попытка 1 — по маске сегментации (надёжно на контрастном фоне).
      List<List<double>>? bestQuad = _bestQuadFromBinary(closed, imageArea);
      final bool maskFound = bestQuad != null;

      // Попытка 2 (фолбэк) — по краям (Canny): работает на СВЕТЛОМ фоне и для
      // листов, которые сегментация не считает «объектом».
      bestQuad ??= _bestQuadByEdges(small, imageArea);

      debugPrint('DocumentScanner: маска=${maskFound ? "✓" : "✗"} '
          'края=${maskFound ? "—" : (bestQuad != null ? "✓" : "✗")}');

      if (bestQuad == null) {
        debugPrint('DocumentScanner: лист не найден → возвращаю оригинал');
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
      if (outWidth < 120 || outHeight < 120) return input;

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
        '${input.parent.path}/documentcrop_'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(encoded);
      debugPrint('DocumentScanner: обрезано ${outWidth}x$outHeight');
      return output;
    } catch (error) {
      debugPrint('DocumentScanner: $error');
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
      if (area < imageArea * _minAreaRatio || area > imageArea * _maxAreaRatio) {
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
          bestQuad =
              corners.map((p) => [p.x.toDouble(), p.y.toDouble()]).toList();
          corners.dispose();
        }
      }
      rect.dispose();
    }
    return bestQuad;
  }

  /// Поиск листа по бинарной маске (сегментация).
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

  /// Поиск листа по краям (Canny) — фолбэк для светлого фона.
  static List<List<double>>? _bestQuadByEdges(cv.Mat small, double imageArea) {
    cv.Mat? gray, blurred, edges, kernel, closed;
    cv.VecVecPoint? contours;
    try {
      gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);
      edges = cv.canny(blurred, 50.0, 150.0);
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
}
