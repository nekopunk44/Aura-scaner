import 'package:flutter/material.dart';

/// Рамка-трафарет для позиционирования документа в кадре.
///
/// Рисует затемнение вокруг выреза, скруглённый вырез с уголками-скобками
/// (как в нативных сканерах) и подпись-подсказку под рамкой. Используется
/// и в авто-, и в ручном режиме съёмки: пользователь всегда видит, куда
/// поместить ID-карту / паспорт.
class DocumentGuideFrame extends StatelessWidget {
  /// Соотношение сторон выреза (ширина / высота).
  /// ID-1 карта — 1.586, страница паспорта — ~1.42 (в альбомной ориентации).
  final double aspectRatio;

  /// Доля ширины экрана, которую занимает вырез.
  final double widthFactor;

  /// Вертикальное положение центра выреза (-1..1, как Alignment.y).
  final double verticalAlignment;

  /// Документ найден детектором — рамка подсвечивается зелёным.
  final bool detected;

  /// Подпись под рамкой (например «Поместите карту в рамку»).
  final String? label;

  /// Иконка-силуэт по центру выреза (подсказка что снимать).
  final IconData? icon;

  /// Рисовать ли затемнение вокруг выреза. Внутри камеры затемнение
  /// рисует ОБЩИЙ постоянный слой (вырез плавно морфится между режимами
  /// и не мигает при переключении) — там передаётся false.
  final bool drawScrim;

  const DocumentGuideFrame({
    super.key,
    required this.aspectRatio,
    this.widthFactor = 0.85,
    this.verticalAlignment = -0.25,
    this.detected = false,
    this.label,
    this.icon,
    this.drawScrim = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final frameWidth = w * widthFactor;
        final frameHeight = frameWidth / aspectRatio;
        final centerY = h / 2 + verticalAlignment * (h / 2 - frameHeight / 2);
        final rect = Rect.fromCenter(
          center: Offset(w / 2, centerY),
          width: frameWidth,
          height: frameHeight,
        );

        final accent =
            detected ? const Color(0xFF35D07F) : Colors.white;

        return IgnorePointer(
          child: Stack(
            children: [
              // Затемнение вокруг выреза
              if (drawScrim)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScrimPainter(cutout: rect),
                  ),
                ),
              // Уголки-скобки
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: CustomPaint(
                    painter: CornerBracketsPainter(
                      cutout: rect,
                      color: accent,
                    ),
                  ),
                ),
              ),
              // Силуэт-подсказка по центру
              if (icon != null)
                Positioned(
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: Center(
                    child: Icon(
                      icon,
                      size: frameHeight * 0.42,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              // Подпись под рамкой
              if (label != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: rect.bottom + 14,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        key: ValueKey<bool>(detected),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: detected
                                ? const Color(0xFF35D07F)
                                : Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScrimPainter extends CustomPainter {
  final Rect cutout;
  const _ScrimPainter({required this.cutout});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(14)));
    final scrim = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) =>
      oldDelegate.cutout != cutout;
}

class CornerBracketsPainter extends CustomPainter {
  final Rect cutout;
  final Color color;
  const CornerBracketsPainter({required this.cutout, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const cornerLen = 26.0;
    const radius = 14.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final r = cutout;

    // Каждый уголок: дуга скругления + два коротких луча.
    // Верхний левый
    final path = Path()
      ..moveTo(r.left, r.top + radius + cornerLen)
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.left + radius + cornerLen, r.top)
      // Верхний правый
      ..moveTo(r.right - radius - cornerLen, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(
        Offset(r.right, r.top + radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.right, r.top + radius + cornerLen)
      // Нижний правый
      ..moveTo(r.right, r.bottom - radius - cornerLen)
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.right - radius - cornerLen, r.bottom)
      // Нижний левый
      ..moveTo(r.left + radius + cornerLen, r.bottom)
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.left, r.bottom - radius - cornerLen);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CornerBracketsPainter oldDelegate) =>
      oldDelegate.cutout != cutout || oldDelegate.color != color;
}
