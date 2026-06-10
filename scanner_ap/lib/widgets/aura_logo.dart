import 'package:flutter/material.dart';

/// Брендовый логотип Aura Scanner.
///
/// Концепция: монограмма «A» как страница-призма, через которую проходит
/// горизонтальный луч сканера. Внутри верхней половины — миниатюрный
/// «документ» со складкой угла (привязка к функции приложения), вокруг
/// буквы — мягкое голубое сияние («аура»).
///
/// Полностью векторный (CustomPainter), без файлов-картинок — чёткий на
/// любом размере, подходит как для splash (160px), так и для launcher-
/// иконки (1024px).
class AuraLogo extends StatelessWidget {
  final double size;
  final Color color;

  /// Светлый акцент для градиента и луча сканера. По умолчанию — светлый
  /// оттенок основного цвета.
  final Color highlight;

  const AuraLogo({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF2CA5E0),
    this.highlight = const Color(0xFF8CDDFF),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AuraLogoPainter(color: color, highlight: highlight),
      ),
    );
  }
}

class _AuraLogoPainter extends CustomPainter {
  final Color color;
  final Color highlight;

  _AuraLogoPainter({required this.color, required this.highlight});

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // 1. Aurora-glow — два радиальных слоя свечения за буквой.
    _drawAura(canvas, base, cx, cy);

    // 2. Геометрия буквы A.
    final aHeight = base * 0.68;
    final aWidth = base * 0.58;
    final aTop = cy - aHeight * 0.52;
    final aBottom = cy + aHeight * 0.48;
    final aLeft = cx - aWidth / 2;
    final aRight = cx + aWidth / 2;

    // Внутренний треугольник — «дыра» в букве A.
    final innerInset = base * 0.085;
    final innerTopY = aTop + innerInset * 1.6;
    final innerBottomY = aBottom - innerInset * 0.4;
    final innerLeftX = aLeft + innerInset;
    final innerRightX = aRight - innerInset;

    // 3. Заливка буквы — диагональный градиент.
    final rect = Rect.fromLTWH(aLeft, aTop, aWidth, aHeight);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [highlight, color],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final letterPath = Path()
      ..fillType = PathFillType.evenOdd
      // Внешний контур треугольника.
      ..moveTo(cx, aTop)
      ..lineTo(aRight, aBottom)
      ..lineTo(aLeft, aBottom)
      ..close()
      // Внутренний контур — даёт «дыру» в треугольнике.
      ..moveTo(cx, innerTopY)
      ..lineTo(innerRightX, innerBottomY)
      ..lineTo(innerLeftX, innerBottomY)
      ..close();

    canvas.drawPath(letterPath, fillPaint);

    // 4. Перекладина-сканер: яркая горизонтальная полоса через центр.
    //    Вписана точно в внешний треугольник + ярче основного градиента.
    final barY = cy + base * 0.04;
    final barTickness = base * 0.06;
    final tFromTop = (barY - aTop) / aHeight;
    final barHalfWidth = (aWidth / 2) * tFromTop;
    final barRect = Rect.fromCenter(
      center: Offset(cx, barY),
      width: barHalfWidth * 2,
      height: barTickness,
    );
    final barPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          highlight.withValues(alpha: 0.9),
          Colors.white,
          highlight.withValues(alpha: 0.9),
        ],
      ).createShader(barRect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, Radius.circular(barTickness / 2)),
      barPaint,
    );

    // 5. Луч сканера выходит за пределы буквы — две короткие линии
    //    наружу слева и справа, как «луч продолжается».
    final rayPaint = Paint()
      ..color = highlight.withValues(alpha: 0.55)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barTickness * 0.45;
    final rayLength = base * 0.08;
    canvas.drawLine(
      Offset(cx - barHalfWidth - base * 0.02, barY),
      Offset(cx - barHalfWidth - base * 0.02 - rayLength, barY),
      rayPaint,
    );
    canvas.drawLine(
      Offset(cx + barHalfWidth + base * 0.02, barY),
      Offset(cx + barHalfWidth + base * 0.02 + rayLength, barY),
      rayPaint,
    );

    // 6. Миниатюрный документ внутри верхней «дыры» буквы — связка с
    //    функцией приложения. Прямоугольник со складкой правого верхнего
    //    угла.
    _drawTinyDocument(
      canvas,
      base: base,
      cx: cx,
      topY: innerTopY,
      barY: barY,
      barTickness: barTickness,
    );

    // 7. Сияющий блик в верхней вершине A — «искра ауры».
    final sparklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, base * 0.012);
    canvas.drawCircle(Offset(cx, aTop + base * 0.005), base * 0.018, sparklePaint);
  }

  void _drawAura(Canvas canvas, double base, double cx, double cy) {
    // Три радиальных слоя — внешний размытый, средний и плотное ядро.
    final auraCenter = Offset(cx, cy);
    final outer = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.28),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: auraCenter, radius: base * 0.55));
    canvas.drawCircle(auraCenter, base * 0.55, outer);

    final middle = Paint()
      ..shader = RadialGradient(
        colors: [
          highlight.withValues(alpha: 0.32),
          highlight.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: auraCenter, radius: base * 0.36));
    canvas.drawCircle(auraCenter, base * 0.36, middle);
  }

  void _drawTinyDocument(
    Canvas canvas, {
    required double base,
    required double cx,
    required double topY,
    required double barY,
    required double barTickness,
  }) {
    // Документ занимает ~80% высоты «дыры» над перекладиной.
    final docTop = topY + base * 0.04;
    final docBottom = barY - barTickness * 0.85;
    final docHeight = docBottom - docTop;
    final docWidth = docHeight * 0.78;
    final docLeft = cx - docWidth / 2;
    final docRight = cx + docWidth / 2;
    final fold = base * 0.04;
    final radius = base * 0.012;

    final path = Path()
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

    // Белая страница чуть просвечивает — пользователь должен видеть
    // градиент «А» под документом, чтобы не было плоско.
    final docPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
    canvas.drawPath(path, docPaint);

    // Складка уголка.
    final foldPath = Path()
      ..moveTo(docRight - fold, docTop)
      ..lineTo(docRight - fold, docTop + fold)
      ..lineTo(docRight, docTop + fold)
      ..close();
    final foldPaint = Paint()..color = color.withValues(alpha: 0.35);
    canvas.drawPath(foldPath, foldPaint);

    // Две линии «текста» в документе.
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = base * 0.012
      ..strokeCap = StrokeCap.round;
    final lineLeft = docLeft + base * 0.018;
    final lineRight = docRight - base * 0.02;
    final firstLineY = docTop + base * 0.045;
    canvas.drawLine(
      Offset(lineLeft, firstLineY),
      Offset(lineRight - base * 0.02, firstLineY),
      linePaint,
    );
    canvas.drawLine(
      Offset(lineLeft, firstLineY + base * 0.03),
      Offset(lineRight - base * 0.06, firstLineY + base * 0.03),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_AuraLogoPainter old) =>
      old.color != color || old.highlight != highlight;
}
