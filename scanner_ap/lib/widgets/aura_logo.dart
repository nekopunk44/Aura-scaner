import 'package:flutter/material.dart';

/// Брендовый логотип Aura Scanner — типографическая монограмма «AS»
/// с перекрытием букв и градиентной заливкой по диагонали.
///
/// - Размер `size` управляет масштабом полного блока (буквы + glow).
/// - `color` — основной акцент (заливка низа).
/// - `highlight` — светлый акцент (заливка верха).
class AuraLogo extends StatelessWidget {
  final double size;
  final Color color;
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
        painter: _AuraLogoPainter(
          color: color,
          highlight: highlight,
        ),
      ),
    );
  }
}

class _AuraLogoPainter extends CustomPainter {
  final Color color;
  final Color highlight;

  _AuraLogoPainter({
    required this.color,
    required this.highlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Подложка-glow: лёгкое радиальное свечение за буквами для объёма.
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(cx, cy),
        radius: base * 0.55,
      ));
    canvas.drawCircle(Offset(cx, cy), base * 0.55, glowPaint);

    // Параметры шрифта.
    final fontSize = base * 0.78;
    final fillColor = color;
    final overlayColor = highlight;

    // Базовый стиль букв.
    TextStyle styleFor(Color c, double weight) => TextStyle(
          fontSize: fontSize,
          color: c,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: -base * 0.02,
        );

    // 1. Буква S — рисуется первой, чтобы A легла поверх и создалось
    //    ощущение «A заходит на S». Сдвинута вправо.
    final sPainter = TextPainter(
      text: TextSpan(text: 'S', style: styleFor(overlayColor, 900)),
      textDirection: TextDirection.ltr,
    )..layout();
    final sOffset = Offset(
      cx - sPainter.width / 2 + base * 0.18,
      cy - sPainter.height / 2,
    );
    sPainter.paint(canvas, sOffset);

    // 2. Буква A — сдвинута влево, частично перекрывает S.
    //    Заливка — диагональный градиент акцента.
    final aPainter = TextPainter(
      text: TextSpan(text: 'A', style: styleFor(fillColor, 900)),
      textDirection: TextDirection.ltr,
    )..layout();
    final aOffset = Offset(
      cx - aPainter.width / 2 - base * 0.18,
      cy - aPainter.height / 2,
    );

    // Применяем градиент через ShaderMask-эквивалент: рисуем букву A
    // и потом накрываем shader-прямоугольником с BlendMode.srcIn — это
    // даёт градиентную заливку формы текста.
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
    aPainter.paint(canvas, aOffset);
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [highlight, color],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(
        aOffset.dx,
        aOffset.dy,
        aPainter.width,
        aPainter.height,
      ))
      ..blendMode = BlendMode.srcIn;
    canvas.drawRect(
      Rect.fromLTWH(
        aOffset.dx,
        aOffset.dy,
        aPainter.width,
        aPainter.height,
      ),
      gradientPaint,
    );
    canvas.restore();

    // 3. Тонкая горизонтальная линия-«подчёркивание» под монограммой —
    //    напоминает скан-линию, не перегружает композицию.
    final underlinePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = base * 0.025
      ..strokeCap = StrokeCap.round;
    final lineY = cy + fontSize * 0.42;
    final lineLeft = cx - base * 0.18;
    final lineRight = cx + base * 0.18;
    canvas.drawLine(
      Offset(lineLeft, lineY),
      Offset(lineRight, lineY),
      underlinePaint,
    );
  }

  @override
  bool shouldRepaint(_AuraLogoPainter old) =>
      old.color != color || old.highlight != highlight;
}
