import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:opencv_core/opencv.dart' as cv;

/// Авто-обрезка ID-карты до самой карты («скан как на принтере»).
///
/// Пайплайн: ML Kit Subject Segmentation отделяет передний объект (карту) от
/// фона (ковёр/стол/пол) — обученной моделью, что надёжнее яркости/краёв. По
/// маске переднего плана OpenCV находит прямоугольник карты (minAreaRect) и
/// выправляет перспективу (warpPerspective). При неуверенности — возвращает
/// исходный файл (без регресса).
class IdCardScanner {
  /// Ширина уменьшенной копии для сегментации/поиска контура.
  static const int _procWidth = 600;

  static Future<File> autoCrop(File input) async {
    SubjectSegmenter? segmenter;
    cv.Mat? src, small, maskMat, kernel, closed, warped, m;
    cv.VecPoint? srcQuad, dstQuad;
    File? tempSmall;
    try {
      final bytes = await input.readAsBytes();
      src = cv.imdecode(bytes, cv.IMREAD_COLOR);
      if (src.isEmpty) return input;
      final int fullW = src.cols;
      final int fullH = src.rows;
      if (fullW < 100 || fullH < 100) return input;

      final double scale = fullW / _procWidth;
      final int procH = (fullH / scale).round();

      // Уменьшенная копия → временный файл для сегментации (память/скорость).
      small = cv.resize(src, (_procWidth, procH));
      final (encOk, smallJpg) = cv.imencode('.jpg', small);
      if (!encOk) return input;
      final dir = await getTemporaryDirectory();
      tempSmall = File(
        '${dir.path}/seg_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await tempSmall.writeAsBytes(smallJpg);

      // --- ML Kit Subject Segmentation: маска переднего плана (карта) ---
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
      final result =
          await segmenter.processImage(InputImage.fromFilePath(tempSmall.path));
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) {
        debugPrint('IdCardScanner: маска пустая → откат');
        return input;
      }
      if (mask.length != _procWidth * procH) {
        // ML Kit вернул маску иного разрешения — без размеров обработать нельзя.
        debugPrint('IdCardScanner: размер маски ${mask.length} != '
            '${_procWidth * procH} → откат');
        return input;
      }

      // Бинарная маска: передний план (карта) = 255.
      final bin = List<int>.generate(mask.length, (i) => mask[i] > 0.5 ? 255 : 0);
      maskMat = cv.Mat.fromList(procH, _procWidth, cv.MatType.CV_8UC1, bin);
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
      closed = cv.morphologyEx(maskMat, cv.MORPH_CLOSE, kernel);

      final (contours, hierarchy) =
          cv.findContours(closed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      hierarchy.dispose();

      final double imgArea = (_procWidth * procH).toDouble();
      debugPrint('IdCardScanner: контуров=${contours.length} (маска сегментации)');
      List<List<double>>? bestQuad;
      double bestArea = 0, dbgArea = 0, dbgRectng = 0, dbgRatio = 0;
      for (final c in contours) {
        final double area = cv.contourArea(c);
        if (area < imgArea * 0.05) continue;
        final rect = cv.minAreaRect(c);
        final double rw = rect.size.width;
        final double rh = rect.size.height;
        final double rectArea = rw * rh;
        if (rectArea >= 1) {
          final double rectng = area / rectArea;
          final double longer = math.max(rw, rh);
          final double shorter = math.min(rw, rh);
          final double ratio = shorter < 1 ? 0 : longer / shorter;
          if (area > dbgArea) {
            dbgArea = area;
            dbgRectng = rectng;
            dbgRatio = ratio;
          }
          if (area >= imgArea * 0.15 &&
              area <= imgArea * 0.99 &&
              rectng >= 0.70 &&
              ratio >= 1.15 &&
              ratio <= 2.7 &&
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
      contours.dispose();
      debugPrint('IdCardScanner: крупнейший area='
          '${(dbgArea / imgArea * 100).toStringAsFixed(0)}% '
          'rectng=${dbgRectng.toStringAsFixed(2)} '
          'ratio=${dbgRatio.toStringAsFixed(2)}');

      if (bestQuad == null) {
        debugPrint('IdCardScanner: прямоугольник карты не найден → откат');
        return input;
      }

      // Углы → исходное разрешение, выправление перспективы.
      final pts = bestQuad.map((p) => [p[0] * scale, p[1] * scale]).toList();
      final ordered = _orderCorners(pts);
      final double wTop = _dist(ordered[0], ordered[1]);
      final double wBot = _dist(ordered[3], ordered[2]);
      final double hL = _dist(ordered[0], ordered[3]);
      final double hR = _dist(ordered[1], ordered[2]);
      final int outW = math.max(wTop, wBot).round();
      final int outH = math.max(hL, hR).round();
      if (outW < 100 || outH < 60) return input;

      srcQuad = cv.VecPoint.fromList(
        ordered.map((o) => cv.Point(o[0].round(), o[1].round())).toList(),
      );
      dstQuad = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(outW - 1, 0),
        cv.Point(outW - 1, outH - 1),
        cv.Point(0, outH - 1),
      ]);
      m = cv.getPerspectiveTransform(srcQuad, dstQuad);
      warped = cv.warpPerspective(src, m, (outW, outH));

      final (warpOk, encoded) = cv.imencode('.jpg', warped);
      if (!warpOk) return input;
      final out = File(
        '${input.parent.path}/idcrop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(encoded);
      debugPrint('IdCardScanner: обрезано до ${outW}x$outH (ML Kit + OpenCV)');
      return out;
    } catch (e) {
      debugPrint('IdCardScanner: ошибка: $e');
      return input;
    } finally {
      await segmenter?.close();
      src?.dispose();
      small?.dispose();
      maskMat?.dispose();
      kernel?.dispose();
      closed?.dispose();
      warped?.dispose();
      m?.dispose();
      srcQuad?.dispose();
      dstQuad?.dispose();
      if (tempSmall != null) {
        try {
          await tempSmall.delete();
        } catch (_) {}
      }
    }
  }

  /// Упорядочивает 4 точки как [tl, tr, br, bl] по суммам/разностям координат.
  static List<List<double>> _orderCorners(List<List<double>> pts) {
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

  static double _dist(List<double> a, List<double> b) {
    final double dx = a[0] - b[0];
    final double dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }
}
