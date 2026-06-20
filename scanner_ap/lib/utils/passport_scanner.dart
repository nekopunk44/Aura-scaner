import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
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
  static const int _procWidth = 600;
  static const double _minAreaRatio = 0.05;
  static const double _maxAreaRatio = 0.99;
  static const double _minRectangularity = 0.70;
  static const double _minAspectRatio = 1.18;
  static const double _maxAspectRatio = 1.90;

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

      final (contours, hierarchy) = cv.findContours(
        closed,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      hierarchy.dispose();

      final imageArea = (_procWidth * procHeight).toDouble();
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
                .map((point) => [point.x.toDouble(), point.y.toDouble()])
                .toList();
            corners.dispose();
          }
        }

        rect.dispose();
      }
      contours.dispose();

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
      return output;
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
