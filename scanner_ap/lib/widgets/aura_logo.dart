import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Брендовый логотип Aura Scanner — «голограмма»: страница документа,
/// которую сканирующий луч превращает из бумаги (ниже луча) в светящийся
/// цифровой каркас (выше луча), вокруг — кольцо ауры.
///
/// Рисуется через CustomPaint в системе координат 512×512 (совпадает с
/// SVG-исходниками в branding/), масштабируется под [size].
///
/// [animate] = true (splash): луч ездит по странице, граница
/// «бумага/голограмма» движется вместе с ним, кольцо вращается, частицы
/// отрываются от угла. false (login/onboarding): статичный кадр с лучом
/// по центру — Hero-переход между экранами интерполирует только размер.
class AuraLogo extends StatefulWidget {
  final double size;
  final Color color;
  final Color highlight;
  final bool animate;

  const AuraLogo({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF2CA5E0),
    this.highlight = const Color(0xFF8CDDFF),
    this.animate = false,
  });

  @override
  State<AuraLogo> createState() => _AuraLogoState();
}

class _AuraLogoState extends State<AuraLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Один цикл = 3 прохода луча + полный оборот кольца.
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 12600),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _AuraLogoPainter painterFor(double t) => _AuraLogoPainter(
          t: t,
          animate: widget.animate,
          color: widget.color,
          highlight: widget.highlight,
        );

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _ctrl == null
            ? CustomPaint(painter: painterFor(0))
            : AnimatedBuilder(
                animation: _ctrl!,
                builder: (_, __) =>
                    CustomPaint(painter: painterFor(_ctrl!.value)),
              ),
      ),
    );
  }
}

class _AuraLogoPainter extends CustomPainter {
  final double t;
  final bool animate;
  final Color color;
  final Color highlight;

  _AuraLogoPainter({
    required this.t,
    required this.animate,
    required this.color,
    required this.highlight,
  });

  static const _center = Offset(256, 260);
  static const _neon = Color(0xFF7FD4FF);
  static const _holoStroke = Color(0xFF8FE0FF);
  static const _ringColor = Color(0xFF5BC0EF);
  static const _beamCore = Color(0xFF9FE0FF);
  static const _paperLine = Color(0xFFC3D2E6);

  // Контур страницы со «срезанным» верхним правым углом (как в SVG).
  static final Path _page = Path()
    ..moveTo(186, 130)
    ..lineTo(296, 130)
    ..lineTo(346, 180)
    ..lineTo(346, 370)
    ..quadraticBezierTo(346, 390, 326, 390)
    ..lineTo(186, 390)
    ..quadraticBezierTo(166, 390, 166, 370)
    ..lineTo(166, 150)
    ..quadraticBezierTo(166, 130, 186, 130)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);

    // Фаза луча: 3 прохода за цикл, ease через косинус. Статично — центр.
    final beamY =
        animate ? 262 + 2 - 60 * math.cos(6 * math.pi * t) : 262.0;
    final pulse = animate ? 0.7 + 0.3 * math.sin(6 * math.pi * t) : 1.0;

    _drawGlow(canvas, pulse);
    _drawRing(canvas);
    _drawPaperPart(canvas, beamY);
    _drawHoloPart(canvas, beamY);
    _drawBeam(canvas, beamY);

    canvas.restore();
  }

  void _drawGlow(Canvas canvas, double pulse) {
    final glowPaint = Paint()
      ..shader = RadialGradient(colors: [
        color.withValues(alpha: 0.30 * pulse),
        color.withValues(alpha: 0.0),
      ], stops: const [0.4, 1.0])
          .createShader(Rect.fromCircle(center: _center, radius: 200));
    canvas.drawCircle(_center, 200, glowPaint);
  }

  void _drawRing(Canvas canvas) {
    // Кольцо r158 с двумя разрывами (длины дуг — как dasharray в SVG).
    const r = 158.0;
    const circumference = 2 * math.pi * r;
    const a1 = 330 / circumference * 2 * math.pi;
    const gap = 90 / circumference * 2 * math.pi;
    const a2 = 480 / circumference * 2 * math.pi;
    final start = -20 * math.pi / 180 + (animate ? 2 * math.pi * t : 0);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = _ringColor.withValues(alpha: 0.7);
    final rect = Rect.fromCircle(center: _center, radius: r);
    canvas.drawArc(rect, start, a1, false, ringPaint);
    canvas.drawArc(rect, start + a1 + gap, a2, false, ringPaint);
  }

  void _rotatePage(Canvas canvas) {
    canvas.translate(_center.dx, _center.dy);
    canvas.rotate(-6 * math.pi / 180);
    canvas.translate(-_center.dx, -_center.dy);
  }

  void _drawPaperPart(Canvas canvas, double beamY) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, beamY, 512, 512));
    _rotatePage(canvas);

    canvas.drawShadow(_page, const Color(0xFF06101F), 12, false);
    final paperPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFE9F2FC)],
      ).createShader(const Rect.fromLTRB(166, 130, 346, 390));
    canvas.drawPath(_page, paperPaint);

    final linePaint = Paint()..color = _paperLine;
    _line(canvas, 186, 292, 124, linePaint);
    _line(canvas, 186, 328, 88, linePaint);
    canvas.restore();
  }

  void _drawHoloPart(Canvas canvas, double beamY) {
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, 512, beamY));
    _rotatePage(canvas);

    canvas.drawPath(_page, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      _page,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..color = _holoStroke,
    );

    final neonPaint = Paint()..color = _neon;
    _line(canvas, 186, 188, 124, neonPaint);
    _line(canvas, 186, 224, 92, neonPaint);

    _drawParticles(canvas);
    canvas.restore();
  }

  void _drawParticles(Canvas canvas) {
    // Три «пикселя», отрывающиеся от срезанного угла.
    const bases = [
      (Offset(312, 116), 20.0),
      (Offset(342, 142), 14.0),
      (Offset(336, 96), 11.0),
    ];
    for (var i = 0; i < bases.length; i++) {
      final (base, side) = bases[i];
      double opacity;
      Offset shift;
      if (animate) {
        final progress = (t * 3 + i / 3) % 1.0;
        opacity = math.sin(math.pi * progress);
        shift = Offset(-8 + 20 * progress, 18 - 52 * progress);
      } else {
        opacity = 0.9 - i * 0.15;
        shift = Offset.zero;
      }
      final paint = Paint()
        ..color = (i == 0 ? _beamCore : const Color(0xFF7FC6EC))
            .withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(base.dx + shift.dx, base.dy + shift.dy, side, side),
          Radius.circular(side * 0.3),
        ),
        paint,
      );
    }
  }

  void _drawBeam(Canvas canvas, double beamY) {
    final gradient = LinearGradient(
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.7),
        _beamCore,
        color.withValues(alpha: 0.7),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
    );
    final bodyRect = Rect.fromLTWH(100, beamY - 9, 312, 18);
    final shader = gradient.createShader(bodyRect);

    // Размытое свечение под лучом.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(100, beamY - 12, 312, 24),
        const Radius.circular(12),
      ),
      Paint()
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // Тело и белое ядро.
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, const Radius.circular(9)),
      Paint()..shader = shader,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(160, beamY - 4, 192, 8),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    // Эмиттеры на концах.
    final emitter = Paint()..color = _beamCore;
    canvas.drawCircle(Offset(100, beamY), 9, emitter);
    canvas.drawCircle(Offset(412, beamY), 9, emitter);
  }

  void _line(Canvas canvas, double x, double y, double w, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, 20),
        const Radius.circular(10),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_AuraLogoPainter old) =>
      old.t != t ||
      old.animate != animate ||
      old.color != color ||
      old.highlight != highlight;
}
