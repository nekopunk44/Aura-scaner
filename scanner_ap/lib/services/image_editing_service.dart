import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;
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

List<List<double>> _detectWatermarkRegionsWork(Uint8List imageBytes) {
  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) {
    throw Exception('Не удаётся декодировать изображение');
  }

  const maxSide = 900;
  final longest = math.max(image.width, image.height);
  if (longest > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }

  final cellSize = math.max(
    3,
    (math.min(image.width, image.height) / 170).round(),
  );
  final columns = (image.width / cellSize).ceil();
  final rows = (image.height / cellSize).ceil();
  final edgeCounts = List<int>.filled(columns * rows, 0);
  final sampleCounts = List<int>.filled(columns * rows, 0);

  double luminance(int x, int y) {
    final pixel = image!.getPixelSafe(x, y);
    return pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114;
  }

  for (var y = 1; y < image.height - 1; y++) {
    for (var x = 1; x < image.width - 1; x++) {
      final horizontal = (luminance(x + 1, y) - luminance(x - 1, y)).abs();
      final vertical = (luminance(x, y + 1) - luminance(x, y - 1)).abs();
      final index = (y ~/ cellSize) * columns + (x ~/ cellSize);
      sampleCounts[index]++;
      if (horizontal + vertical >= 34) {
        edgeCounts[index]++;
      }
    }
  }

  final active = List<bool>.generate(columns * rows, (index) {
    final samples = sampleCounts[index];
    if (samples == 0) return false;
    final density = edgeCounts[index] / samples;
    return edgeCounts[index] >= 2 && density >= 0.10 && density <= 0.78;
  });

  // Connect nearby strokes into words and logos without joining distant objects.
  final grouped = List<bool>.filled(active.length, false);
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      if (!active[row * columns + column]) continue;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -4; dx <= 4; dx++) {
          final nextColumn = column + dx;
          final nextRow = row + dy;
          if (nextColumn >= 0 &&
              nextColumn < columns &&
              nextRow >= 0 &&
              nextRow < rows) {
            grouped[nextRow * columns + nextColumn] = true;
          }
        }
      }
    }
  }

  final visited = List<bool>.filled(grouped.length, false);
  final candidates = <({Rect rect, double score})>[];
  for (var start = 0; start < grouped.length; start++) {
    if (!grouped[start] || visited[start]) continue;
    final queue = <int>[start];
    visited[start] = true;
    var queueIndex = 0;
    var minColumn = start % columns;
    var maxColumn = minColumn;
    var minRow = start ~/ columns;
    var maxRow = minRow;

    while (queueIndex < queue.length) {
      final index = queue[queueIndex++];
      final column = index % columns;
      final row = index ~/ columns;
      minColumn = math.min(minColumn, column);
      maxColumn = math.max(maxColumn, column);
      minRow = math.min(minRow, row);
      maxRow = math.max(maxRow, row);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nextColumn = column + dx;
          final nextRow = row + dy;
          if (nextColumn < 0 ||
              nextColumn >= columns ||
              nextRow < 0 ||
              nextRow >= rows) {
            continue;
          }
          final nextIndex = nextRow * columns + nextColumn;
          if (grouped[nextIndex] && !visited[nextIndex]) {
            visited[nextIndex] = true;
            queue.add(nextIndex);
          }
        }
      }
    }

    final left = minColumn * cellSize;
    final top = minRow * cellSize;
    final right = math.min(image.width, (maxColumn + 1) * cellSize);
    final bottom = math.min(image.height, (maxRow + 1) * cellSize);
    final width = right - left;
    final height = bottom - top;
    final widthRatio = width / image.width;
    final heightRatio = height / image.height;
    final areaRatio = widthRatio * heightRatio;
    if (widthRatio < 0.08 ||
        heightRatio < 0.018 ||
        areaRatio < 0.0015 ||
        areaRatio > 0.42) {
      continue;
    }

    var regionEdges = 0;
    var regionSamples = 0;
    for (var row = minRow; row <= maxRow; row++) {
      for (var column = minColumn; column <= maxColumn; column++) {
        final index = row * columns + column;
        regionEdges += edgeCounts[index];
        regionSamples += sampleCounts[index];
      }
    }
    final edgeDensity = regionSamples == 0 ? 0.0 : regionEdges / regionSamples;
    if (edgeDensity < 0.025 || edgeDensity > 0.55) continue;

    final aspect = width / math.max(1, height);
    final centerX = (left + right) / 2 / image.width;
    final centerY = (top + bottom) / 2 / image.height;
    final nearEdge =
        centerX < 0.22 || centerX > 0.78 || centerY < 0.22 || centerY > 0.78;
    if (!nearEdge && widthRatio < 0.20 && aspect < 1.7) continue;

    final score =
        edgeDensity * 120 +
        widthRatio * 45 +
        (nearEdge ? 18 : 0) +
        (aspect >= 1.7 ? 16 : 0) +
        (centerX > 0.22 && centerX < 0.78 && widthRatio > 0.28 ? 10 : 0);
    final horizontalPadding = math.max(4, width * 0.045);
    final verticalPadding = math.max(4, height * 0.16);
    candidates.add((
      rect: Rect.fromLTRB(
        ((left - horizontalPadding) / image.width).clamp(0.0, 1.0),
        ((top - verticalPadding) / image.height).clamp(0.0, 1.0),
        ((right + horizontalPadding) / image.width).clamp(0.0, 1.0),
        ((bottom + verticalPadding) / image.height).clamp(0.0, 1.0),
      ),
      score: score,
    ));
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  final selected = <Rect>[];
  for (final candidate in candidates) {
    final overlapsExisting = selected.any((existing) {
      final intersection = existing.intersect(candidate.rect);
      if (intersection.isEmpty) return false;
      final intersectionArea = intersection.width * intersection.height;
      final smallerArea = math.min(
        existing.width * existing.height,
        candidate.rect.width * candidate.rect.height,
      );
      return smallerArea > 0 && intersectionArea / smallerArea > 0.45;
    });
    if (!overlapsExisting) selected.add(candidate.rect);
    if (selected.length == 32) break;
  }

  return selected
      .map((rect) => [rect.left, rect.top, rect.right, rect.bottom])
      .toList(growable: false);
}

Uint8List _removeSpotInSelectionWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final normalizedLeft = params[1] as double;
  final normalizedTop = params[2] as double;
  final normalizedRight = params[3] as double;
  final normalizedBottom = params[4] as double;
  final maskMode = params.length > 5 ? params[5] : false;
  final fillWholeSelection = maskMode == true;
  final fillAllAnomalies = maskMode == 2;
  final losslessOutput = params.length > 6 && params[6] == true;
  final forbiddenSourceRegions = params.length > 7
      ? ((params[7] as List).cast<List<dynamic>>())
            .map(
              (values) => Rect.fromLTRB(
                values[0] as double,
                values[1] as double,
                values[2] as double,
                values[3] as double,
              ),
            )
            .toList(growable: false)
      : const <Rect>[];

  final image = img.decodeImage(imageBytes);
  if (image == null) {
    throw Exception('Не удаётся декодировать изображение');
  }

  final left = (normalizedLeft * image.width).floor().clamp(0, image.width - 1);
  final top = (normalizedTop * image.height).floor().clamp(0, image.height - 1);
  final right = (normalizedRight * image.width).ceil().clamp(
    left + 1,
    image.width,
  );
  final bottom = (normalizedBottom * image.height).ceil().clamp(
    top + 1,
    image.height,
  );
  final width = right - left;
  final height = bottom - top;
  if (width < 4 || height < 4) {
    return imageBytes;
  }

  final pixelCount = width * height;
  final scores = List<double>.filled(pixelCount, 0);
  final borderDistances = List<double>.filled(pixelCount, 0);
  final sampleRadius = (math.min(width, height) / 10).round().clamp(2, 9);

  double colorDistance(img.Pixel a, img.Pixel b) {
    final dr = a.r.toDouble() - b.r.toDouble();
    final dg = a.g.toDouble() - b.g.toDouble();
    final db = a.b.toDouble() - b.b.toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  double colorDistanceToRgb(img.Pixel pixel, num r, num g, num b) {
    final dr = pixel.r.toDouble() - r.toDouble();
    final dg = pixel.g.toDouble() - g.toDouble();
    final db = pixel.b.toDouble() - b.toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }

  final borderSamples = <img.Pixel>[];
  final borderStep = math.max(1, math.min(width, height) ~/ 24);
  for (var x = left; x < right; x += borderStep) {
    borderSamples.add(image.getPixelSafe(x, math.max(0, top - 2)));
    borderSamples.add(
      image.getPixelSafe(x, math.min(image.height - 1, bottom + 1)),
    );
  }
  for (var y = top; y < bottom; y += borderStep) {
    borderSamples.add(image.getPixelSafe(math.max(0, left - 2), y));
    borderSamples.add(
      image.getPixelSafe(math.min(image.width - 1, right + 1), y),
    );
  }

  final borderR = borderSamples.map((pixel) => pixel.r.toInt()).toList()
    ..sort();
  final borderG = borderSamples.map((pixel) => pixel.g.toInt()).toList()
    ..sort();
  final borderB = borderSamples.map((pixel) => pixel.b.toInt()).toList()
    ..sort();
  final medianIndex = borderSamples.length ~/ 2;
  final medianBorderR = borderR[medianIndex];
  final medianBorderG = borderG[medianIndex];
  final medianBorderB = borderB[medianIndex];

  for (var localY = 0; localY < height; localY++) {
    final y = top + localY;
    for (var localX = 0; localX < width; localX++) {
      final x = left + localX;
      final center = image.getPixelSafe(x, y);
      var localDifference = 0.0;
      var samples = 0;
      for (final offset in <(int, int)>[
        (-sampleRadius, 0),
        (sampleRadius, 0),
        (0, -sampleRadius),
        (0, sampleRadius),
        (-sampleRadius, -sampleRadius),
        (sampleRadius, -sampleRadius),
        (-sampleRadius, sampleRadius),
        (sampleRadius, sampleRadius),
      ]) {
        final sampleX = (x + offset.$1).clamp(0, image.width - 1);
        final sampleY = (y + offset.$2).clamp(0, image.height - 1);
        localDifference += colorDistance(
          center,
          image.getPixelSafe(sampleX, sampleY),
        );
        samples++;
      }
      final borderDifference = colorDistanceToRgb(
        center,
        medianBorderR,
        medianBorderG,
        medianBorderB,
      );
      final index = localY * width + localX;
      borderDistances[index] = borderDifference;
      scores[index] =
          (localDifference / samples) * 0.72 + borderDifference * 0.28;
    }
  }

  final sortedScores = List<double>.from(scores)..sort();
  final medianScore = sortedScores[sortedScores.length ~/ 2];
  final deviations = scores.map((score) => (score - medianScore).abs()).toList()
    ..sort();
  final medianDeviation = deviations[deviations.length ~/ 2];
  final seedThreshold = medianScore + math.max(14, medianDeviation * 2.2);
  final growthThreshold = medianScore + math.max(7, medianDeviation * 0.8);

  var seedIndex = 0;
  var seedScore = -1.0;
  for (var index = 0; index < scores.length; index++) {
    final localX = index % width;
    final localY = index ~/ width;
    final dx = (localX - width / 2) / math.max(1, width / 2);
    final dy = (localY - height / 2) / math.max(1, height / 2);
    final centerWeight = 1 - math.min(0.35, math.sqrt(dx * dx + dy * dy) * 0.2);
    final weightedScore = scores[index] * centerWeight;
    if (weightedScore > seedScore) {
      seedScore = weightedScore;
      seedIndex = index;
    }
  }

  var mask = List<bool>.filled(pixelCount, false);
  if (fillWholeSelection) {
    final inset = (math.min(width, height) * 0.035).round().clamp(2, 8);
    mask = List<bool>.generate(pixelCount, (index) {
      final x = index % width;
      final y = index ~/ width;
      final dx = (x - (width - 1) / 2) / math.max(1, (width - 1) / 2 - inset);
      final dy = (y - (height - 1) / 2) / math.max(1, (height - 1) / 2 - inset);
      return math.pow(dx.abs(), 8) + math.pow(dy.abs(), 8) <= 1;
    });
  } else if (fillAllAnomalies) {
    final percentileThreshold =
        sortedScores[((sortedScores.length - 1) * 0.72).round()];
    final watermarkThreshold = math.max(
      percentileThreshold,
      medianScore + math.max(6, medianDeviation * 0.9),
    );
    final sortedBorderDistances = List<double>.from(borderDistances)..sort();
    final medianBorderDistance =
        sortedBorderDistances[sortedBorderDistances.length ~/ 2];
    final borderDeviations =
        borderDistances
            .map((distance) => (distance - medianBorderDistance).abs())
            .toList()
          ..sort();
    final borderDeviation = borderDeviations[borderDeviations.length ~/ 2];
    final borderThreshold = math.max(
      sortedBorderDistances[((sortedBorderDistances.length - 1) * 0.78)
          .round()],
      medianBorderDistance + math.max(16, borderDeviation * 1.5),
    );
    mask = List<bool>.generate(
      pixelCount,
      (index) =>
          scores[index] >= watermarkThreshold ||
          borderDistances[index] >= borderThreshold,
    );

    final detectedPixels = mask.where((value) => value).length;
    final minimumPixels = math.max(6, (pixelCount * 0.012).round());
    if (detectedPixels < minimumPixels) {
      final fallbackThreshold =
          sortedScores[((sortedScores.length - 1) * 0.82).round()];
      mask = List<bool>.generate(
        pixelCount,
        (index) => scores[index] >= fallbackThreshold,
      );
    }
  } else if (scores[seedIndex] >= seedThreshold) {
    final queue = <int>[seedIndex];
    mask[seedIndex] = true;
    var queueIndex = 0;
    while (queueIndex < queue.length) {
      final index = queue[queueIndex++];
      final x = index % width;
      final y = index ~/ width;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nextX = x + dx;
          final nextY = y + dy;
          if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height) {
            continue;
          }
          final nextIndex = nextY * width + nextX;
          if (!mask[nextIndex] && scores[nextIndex] >= growthThreshold) {
            mask[nextIndex] = true;
            queue.add(nextIndex);
          }
        }
      }
    }
  }

  var maskedCount = mask.where((value) => value).length;
  final minimumMaskSize = math.max(9, (pixelCount * 0.008).round());
  if (!fillWholeSelection &&
      !fillAllAnomalies &&
      maskedCount < minimumMaskSize) {
    // A tight manual selection is itself a useful fallback for low-contrast stains.
    mask = List<bool>.generate(pixelCount, (index) {
      final x = index % width;
      final y = index ~/ width;
      final dx = (x - (width - 1) / 2) / math.max(1, width * 0.46);
      final dy = (y - (height - 1) / 2) / math.max(1, height * 0.46);
      return dx * dx + dy * dy <= 1;
    });
    maskedCount = mask.where((value) => value).length;
  }

  final dilationPasses = fillAllAnomalies
      ? 1
      : math.max(1, (math.min(width, height) / 35).round()).clamp(1, 4);
  for (var pass = 0; pass < dilationPasses; pass++) {
    final expanded = List<bool>.from(mask);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (!mask[index]) continue;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nextX = x + dx;
            final nextY = y + dy;
            if (nextX >= 0 && nextX < width && nextY >= 0 && nextY < height) {
              expanded[nextY * width + nextX] = true;
            }
          }
        }
      }
    }
    mask = expanded;
  }

  if (fillAllAnomalies) {
    final remaining = List<bool>.from(mask);
    var remainingCount = remaining.where((value) => value).length;
    final maxIterations = width + height;

    for (
      var iteration = 0;
      iteration < maxIterations && remainingCount > 0;
      iteration++
    ) {
      final updates = <(int, int, int, int, int)>[];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final index = y * width + x;
          if (!remaining[index]) continue;

          var totalR = 0.0;
          var totalG = 0.0;
          var totalB = 0.0;
          var totalWeight = 0.0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final sampleX = x + dx;
              final sampleY = y + dy;
              if (sampleX < 0 ||
                  sampleX >= width ||
                  sampleY < 0 ||
                  sampleY >= height ||
                  remaining[sampleY * width + sampleX]) {
                continue;
              }
              final pixel = image.getPixelSafe(left + sampleX, top + sampleY);
              final weight = dx == 0 || dy == 0 ? 1.0 : 0.72;
              totalR += pixel.r * weight;
              totalG += pixel.g * weight;
              totalB += pixel.b * weight;
              totalWeight += weight;
            }
          }

          if (totalWeight > 0) {
            final original = image.getPixelSafe(left + x, top + y);
            updates.add((
              index,
              (totalR / totalWeight).round(),
              (totalG / totalWeight).round(),
              (totalB / totalWeight).round(),
              original.a.toInt(),
            ));
          }
        }
      }

      if (updates.isEmpty) break;
      for (final update in updates) {
        final x = update.$1 % width;
        final y = update.$1 ~/ width;
        image.setPixelRgba(
          left + x,
          top + y,
          update.$2,
          update.$3,
          update.$4,
          update.$5,
        );
        remaining[update.$1] = false;
      }
      remainingCount -= updates.length;
    }

    return Uint8List.fromList(
      losslessOutput ? img.encodePng(image) : img.encodeJpg(image, quality: 94),
    );
  }

  final comparisonPoints = <(int, int)>[];
  final comparisonStep = math.max(1, math.min(width, height) ~/ 18);
  for (var y = 0; y < height; y += comparisonStep) {
    for (var x = 0; x < width; x += comparisonStep) {
      final edgeDistance = math.min(
        math.min(x, width - 1 - x),
        math.min(y, height - 1 - y),
      );
      if (edgeDistance <= comparisonStep * 2 && !mask[y * width + x]) {
        comparisonPoints.add((x, y));
      }
    }
  }
  if (comparisonPoints.isEmpty) {
    comparisonPoints.addAll(<(int, int)>[
      (0, 0),
      (width - 1, 0),
      (0, height - 1),
      (width - 1, height - 1),
    ]);
  }

  final searchDistance = (math.max(width, height) * 3).clamp(36, 420);
  final candidateStep = math.max(3, math.min(width, height) ~/ 5);
  final minSourceX = math.max(0, left - searchDistance);
  final maxSourceX = math.min(image.width - width, left + searchDistance);
  final minSourceY = math.max(0, top - searchDistance);
  final maxSourceY = math.min(image.height - height, top + searchDistance);
  var bestSourceX = -1;
  var bestSourceY = -1;
  var bestScore = double.infinity;

  for (
    var sourceY = minSourceY;
    sourceY <= maxSourceY;
    sourceY += candidateStep
  ) {
    for (
      var sourceX = minSourceX;
      sourceX <= maxSourceX;
      sourceX += candidateStep
    ) {
      final overlapsTarget =
          sourceX < right &&
          sourceX + width > left &&
          sourceY < bottom &&
          sourceY + height > top;
      if (overlapsTarget) continue;
      final normalizedSource = Rect.fromLTWH(
        sourceX / image.width,
        sourceY / image.height,
        width / image.width,
        height / image.height,
      );
      if (forbiddenSourceRegions.any(normalizedSource.overlaps)) {
        continue;
      }

      var score = 0.0;
      for (final point in comparisonPoints) {
        score += colorDistance(
          image.getPixelSafe(left + point.$1, top + point.$2),
          image.getPixelSafe(sourceX + point.$1, sourceY + point.$2),
        );
      }
      score /= comparisonPoints.length;
      final distance = math.sqrt(
        math.pow(sourceX - left, 2) + math.pow(sourceY - top, 2),
      );
      score += distance * 0.015;
      if (score < bestScore) {
        bestScore = score;
        bestSourceX = sourceX;
        bestSourceY = sourceY;
      }
    }
  }

  if (bestSourceX < 0 || bestSourceY < 0) {
    return imageBytes;
  }

  var deltaR = 0.0;
  var deltaG = 0.0;
  var deltaB = 0.0;
  for (final point in comparisonPoints) {
    final target = image.getPixelSafe(left + point.$1, top + point.$2);
    final source = image.getPixelSafe(
      bestSourceX + point.$1,
      bestSourceY + point.$2,
    );
    deltaR += target.r.toDouble() - source.r.toDouble();
    deltaG += target.g.toDouble() - source.g.toDouble();
    deltaB += target.b.toDouble() - source.b.toDouble();
  }
  deltaR /= comparisonPoints.length;
  deltaG /= comparisonPoints.length;
  deltaB /= comparisonPoints.length;

  var alphaMask = mask.map((value) => value ? 1.0 : 0.0).toList();
  for (var pass = 0; pass < 3; pass++) {
    final softened = List<double>.filled(pixelCount, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var total = 0.0;
        var count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final sampleX = x + dx;
            final sampleY = y + dy;
            if (sampleX >= 0 &&
                sampleX < width &&
                sampleY >= 0 &&
                sampleY < height) {
              total += alphaMask[sampleY * width + sampleX];
              count++;
            }
          }
        }
        softened[y * width + x] = total / count;
      }
    }
    alphaMask = softened;
  }

  for (var localY = 0; localY < height; localY++) {
    for (var localX = 0; localX < width; localX++) {
      final alpha = alphaMask[localY * width + localX];
      if (alpha <= 0.03) continue;
      final targetX = left + localX;
      final targetY = top + localY;
      final original = image.getPixelSafe(targetX, targetY);
      final source = image.getPixelSafe(
        bestSourceX + localX,
        bestSourceY + localY,
      );
      final correctedR = (source.r.toDouble() + deltaR).clamp(0, 255);
      final correctedG = (source.g.toDouble() + deltaG).clamp(0, 255);
      final correctedB = (source.b.toDouble() + deltaB).clamp(0, 255);
      image.setPixelRgba(
        targetX,
        targetY,
        (original.r * (1 - alpha) + correctedR * alpha).round(),
        (original.g * (1 - alpha) + correctedG * alpha).round(),
        (original.b * (1 - alpha) + correctedB * alpha).round(),
        original.a,
      );
    }
  }

  return Uint8List.fromList(
    losslessOutput ? img.encodePng(image) : img.encodeJpg(image, quality: 94),
  );
}

Uint8List _removeWatermarksInSelectionsWork(List<dynamic> params) {
  final imageBytes = params[0] as Uint8List;
  final rawRegions = (params[1] as List).cast<List<dynamic>>();
  final image = img.decodeImage(imageBytes);
  if (image == null) {
    throw Exception('Не удаётся декодировать изображение');
  }

  for (final values in rawRegions.take(32)) {
    final normalizedLeft = values[0] as double;
    final normalizedTop = values[1] as double;
    final normalizedRight = values[2] as double;
    final normalizedBottom = values[3] as double;
    final left = (normalizedLeft * image.width).floor().clamp(
      0,
      image.width - 1,
    );
    final top = (normalizedTop * image.height).floor().clamp(
      0,
      image.height - 1,
    );
    final right = (normalizedRight * image.width).ceil().clamp(
      left + 1,
      image.width,
    );
    final bottom = (normalizedBottom * image.height).ceil().clamp(
      top + 1,
      image.height,
    );
    final regionWidth = right - left;
    final regionHeight = bottom - top;
    if (regionWidth < 4 || regionHeight < 4) continue;

    final margin = (math.max(regionWidth, regionHeight) * 2.6).round().clamp(
      28,
      520,
    );
    final patchLeft = math.max(0, left - margin);
    final patchTop = math.max(0, top - margin);
    final patchRight = math.min(image.width, right + margin);
    final patchBottom = math.min(image.height, bottom + margin);
    final patchWidth = patchRight - patchLeft;
    final patchHeight = patchBottom - patchTop;
    if (patchWidth <= regionWidth || patchHeight <= regionHeight) continue;

    final patch = img.copyCrop(
      image,
      x: patchLeft,
      y: patchTop,
      width: patchWidth,
      height: patchHeight,
    );
    final forbiddenInPatch = <List<double>>[];
    for (final otherValues in rawRegions) {
      final otherLeft = (otherValues[0] as double) * image.width;
      final otherTop = (otherValues[1] as double) * image.height;
      final otherRight = (otherValues[2] as double) * image.width;
      final otherBottom = (otherValues[3] as double) * image.height;
      final other = Rect.fromLTRB(otherLeft, otherTop, otherRight, otherBottom);
      final patchRect = Rect.fromLTRB(
        patchLeft.toDouble(),
        patchTop.toDouble(),
        patchRight.toDouble(),
        patchBottom.toDouble(),
      );
      if (!patchRect.overlaps(other)) continue;
      forbiddenInPatch.add([
        ((other.left - patchLeft) / patchWidth).clamp(0.0, 1.0),
        ((other.top - patchTop) / patchHeight).clamp(0.0, 1.0),
        ((other.right - patchLeft) / patchWidth).clamp(0.0, 1.0),
        ((other.bottom - patchTop) / patchHeight).clamp(0.0, 1.0),
      ]);
    }
    final processedBytes = _removeSpotInSelectionWork([
      Uint8List.fromList(img.encodePng(patch)),
      (left - patchLeft) / patchWidth,
      (top - patchTop) / patchHeight,
      (right - patchLeft) / patchWidth,
      (bottom - patchTop) / patchHeight,
      2,
      true,
      forbiddenInPatch,
    ]);
    final processedPatch = img.decodeImage(processedBytes);
    if (processedPatch == null) continue;

    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        image.setPixel(
          x,
          y,
          processedPatch.getPixelSafe(x - patchLeft, y - patchTop),
        );
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 94));
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

  static Future<List<Rect>> detectWatermarkRegions({
    required Uint8List imageBytes,
  }) async {
    final regions = await compute(_detectWatermarkRegionsWork, imageBytes);
    return regions
        .map(
          (values) => Rect.fromLTRB(values[0], values[1], values[2], values[3]),
        )
        .toList(growable: false);
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

  static Future<Uint8List> removeSpotInSelection({
    required Uint8List imageBytes,
    required Rect normalizedSelection,
  }) {
    return compute(_removeSpotInSelectionWork, [
      imageBytes,
      normalizedSelection.left,
      normalizedSelection.top,
      normalizedSelection.right,
      normalizedSelection.bottom,
      false,
    ]);
  }

  static Future<Uint8List> removeWatermarkInSelection({
    required Uint8List imageBytes,
    required Rect normalizedSelection,
  }) {
    return compute(_removeSpotInSelectionWork, [
      imageBytes,
      normalizedSelection.left,
      normalizedSelection.top,
      normalizedSelection.right,
      normalizedSelection.bottom,
      2,
    ]);
  }

  static Future<Uint8List> removeWatermarksInSelections({
    required Uint8List imageBytes,
    required List<Rect> normalizedSelections,
  }) {
    return compute(_removeWatermarksInSelectionsWork, [
      imageBytes,
      normalizedSelections
          .map((rect) => [rect.left, rect.top, rect.right, rect.bottom])
          .toList(growable: false),
    ]);
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
