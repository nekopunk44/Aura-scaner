import 'package:flutter/material.dart';

/// Брендовый логотип Aura Scanner. Полностью векторный (CustomPainter),
/// без файлов-картинок: концентрические волны вокруг документа.
///
/// Используется на splash, login и в качестве источника для генерации
/// launcher-иконки Android/iOS.
class AuraLogo extends StatelessWidget {
  final double size;
  final Color color;

  /// Если `true`, центральный документ заливается белым, а волны цветные —
  /// для размещения на цветной плашке (например, splash на акцентном фоне).
  final bool invert;

  const AuraLogo({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF2CA5E0),
    this.invert = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AuraLogoPainter(color: color, invert: invert),
      ),
    );
  }
}

class _AuraLogoPainter extends CustomPainter {
  final Color color;
  final bool invert;

  _AuraLogoPainter({required this.color, required this.invert});

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);

    // Концентрические волны «aura» вокруг документа — 3 круга с убывающей
    // прозрачностью. Создают ощущение луча/ауры сканера.
    for (int i = 0; i < 3; i++) {
      final radius = base * (0.30 + 0.10 * i);
      final strokeWidth = base * 0.018;
      final paint = Paint()
        ..color = color.withValues(alpha: 0.22 - 0.06 * i)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, paint);
    }

    // Документ — прямоугольник со скруглёнными углами и загнутым правым
    // верхним уголком.
    final docW = base * 0.34;
    final docH = base * 0.44;
    final docLeft = center.dx - docW / 2;
    final docTop = center.dy - docH / 2;
    final docRight = docLeft + docW;
    final docBottom = docTop + docH;
    final fold = base * 0.085;
    final radius = base * 0.04;

    final docPath = Path()
      ..moveTo(docLeft + radius, docTop)
      ..lineTo(docRight - fold, docTop)
      ..lineTo(docRight, docTop + fold)
      ..lineTo(docRight, docBottom - radius)
      ..quadraticBezierTo(docRight, docBottom, docRight - radius, docBottom)
      ..lineTo(docLeft + radius, docBottom)
      ..quadraticBezierTo(docLeft, docBottom, docLeft, docBottom - radius)
      ..lineTo(docLeft, docTop + radius)
      ..quadraticBezierTo(docLeft, docTop, docLeft + radius, docTop)
      ..close();

    final docPaint = Paint()
      ..color = invert ? Colors.white : color
      ..style = PaintingStyle.fill;
    canvas.drawPath(docPath, docPaint);

    // Загнутый уголок — небольшой треугольник.
    final foldPath = Path()
      ..moveTo(docRight - fold, docTop)
      ..lineTo(docRight - fold, docTop + fold)
      ..lineTo(docRight, docTop + fold)
      ..close();
    final foldPaint = Paint()
      ..color = (invert ? Colors.white : color).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(foldPath, foldPaint);

    // Три текстовые линии внутри документа.
    final lineColor = invert ? color : Colors.white;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = base * 0.018
      ..strokeCap = StrokeCap.round;
    final lineLeft = docLeft + base * 0.04;
    final lineRight = docRight - base * 0.045;
    final lineMid = docRight - base * 0.10;
    final firstLineY = docTop + base * 0.16;
    final lineGap = base * 0.07;
    for (int i = 0; i < 3; i++) {
      final y = firstLineY + i * lineGap;
      final right = i == 2 ? lineMid : lineRight;
      canvas.drawLine(Offset(lineLeft, y), Offset(right, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(_AuraLogoPainter old) =>
      old.color != color || old.invert != invert;
}
