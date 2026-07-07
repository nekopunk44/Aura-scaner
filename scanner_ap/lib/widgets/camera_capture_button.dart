import 'package:flutter/material.dart';

/// Кнопка съёмки для камеры: вращающееся бело-голубое градиентное кольцо
/// (sweep-gradient, «заряженная» кнопка) + внутренний круг с бликом,
/// glow-тень акцентного цвета, нажимной shrink-эффект.
class CameraCaptureButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;
  final bool isBusy;

  /// Текст внутри кнопки. Используется в режиме multi-page документа,
  /// чтобы показать номер следующей страницы внутри capture-кружка.
  final String? label;

  const CameraCaptureButton({
    super.key,
    required this.onTap,
    this.size = 78,
    this.isBusy = false,
    this.label,
  });

  @override
  State<CameraCaptureButton> createState() => _CameraCaptureButtonState();
}

class _CameraCaptureButtonState extends State<CameraCaptureButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  late final AnimationController _ringCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  )..repeat();

  @override
  void dispose() {
    _ringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.isBusy;
    final size = widget.size;

    return GestureDetector(
      onTapDown: (_) {
        if (enabled) setState(() => _pressed = true);
      },
      onTapUp: (_) {
        if (enabled) setState(() => _pressed = false);
      },
      onTapCancel: () {
        if (_pressed) setState(() => _pressed = false);
      },
      onTap: enabled ? widget.onTap : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Вращающееся градиентное кольцо (статичное серое при disabled).
            Positioned.fill(
              child: enabled
                  ? RotationTransition(
                      turns: _ringCtrl,
                      child: CustomPaint(
                        painter: _GradientRingPainter(),
                      ),
                    )
                  : CustomPaint(
                      painter: _GradientRingPainter(disabled: true),
                    ),
            ),
            // Glow под кнопкой.
            if (enabled)
              Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            // Внутренний круг с бликом.
            AnimatedScale(
              duration: const Duration(milliseconds: 140),
              scale: _pressed ? 0.80 : 1.0,
              curve: Curves.easeOut,
              child: Container(
                width: size * 0.74,
                height: size * 0.74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: enabled
                      ? const RadialGradient(
                          center: Alignment(-0.35, -0.45),
                          radius: 1.15,
                          colors: [
                            Colors.white,
                            Color(0xFFEAF5FD),
                            Color(0xFFCBE6F8),
                          ],
                          stops: [0.0, 0.62, 1.0],
                        )
                      : null,
                  color: enabled ? null : Colors.white.withValues(alpha: 0.25),
                ),
                child: widget.isBusy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF2CA5E0),
                          ),
                        ),
                      )
                    : widget.label != null
                        ? Center(
                            child: Text(
                              widget.label!,
                              style: TextStyle(
                                color: enabled
                                    ? const Color(0xFF1A1A2E)
                                    : Colors.white70,
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                          )
                        : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кольцо с бело-голубым sweep-градиентом — рисуется штрихом по окружности.
class _GradientRingPainter extends CustomPainter {
  final bool disabled;
  const _GradientRingPainter({this.disabled = false});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.6;
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (disabled) {
      paint.color = Colors.white.withValues(alpha: 0.4);
    } else {
      paint.shader = const SweepGradient(
        colors: [
          Colors.white,
          Color(0xFF35B4F4),
          Color(0xFF1687D5),
          Color(0xFF35B4F4),
          Colors.white,
        ],
        stops: [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(rect);
    }

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(_GradientRingPainter oldDelegate) =>
      oldDelegate.disabled != disabled;
}
