import 'dart:math' as math;

import 'package:flutter/material.dart';

class AuthBackground extends StatefulWidget {
  final bool isDark;
  final Widget child;

  const AuthBackground({super.key, required this.isDark, required this.child});

  @override
  State<AuthBackground> createState() => _AuthBackgroundState();
}

class _AuthBackgroundState extends State<AuthBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _particleCtrl;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.isDark
              ? const [Color(0xFF07111F), Color(0xFF0A1728), Color(0xFF0D2136)]
              : const [Color(0xFFE6F0FA), Color(0xFFEDF4FB), Color(0xFFF8FBFE)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (disableAnimations)
            CustomPaint(
              painter: _DigitalParticlesPainter(t: 0.18, isDark: widget.isDark),
            )
          else
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                painter: _DigitalParticlesPainter(
                  t: _particleCtrl.value,
                  isDark: widget.isDark,
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class AuthFormCard extends StatelessWidget {
  final bool isDark;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const AuthFormCard({
    super.key,
    required this.isDark,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF132033).withValues(alpha: 0.86)
            : Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.82),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.20)
                : const Color(0xFF6B9BE8).withValues(alpha: 0.12),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  final bool isLoading;
  final String label;
  final VoidCallback? onPressed;
  final double height;

  const AuthPrimaryButton({
    super.key,
    required this.isLoading,
    required this.label,
    required this.onPressed,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null && !isLoading;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isEnabled || isLoading ? 1 : 0.58,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(15),
          splashColor: Colors.white.withValues(alpha: 0.16),
          child: Ink(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isEnabled || isLoading
                    ? const [Color(0xFF35B4F4), Color(0xFF1687D5)]
                    : [
                        const Color(0xFF35B4F4).withValues(alpha: 0.40),
                        const Color(0xFF1687D5).withValues(alpha: 0.40),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF22A8EA,
                  ).withValues(alpha: isEnabled ? 0.32 : 0.12),
                  blurRadius: 20,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitalParticlesPainter extends CustomPainter {
  final double t;
  final bool isDark;

  const _DigitalParticlesPainter({required this.t, required this.isDark});

  static const _accent = Color(0xFF2CA5E0);
  static const _bases = [
    Offset(0.06, 0.12),
    Offset(0.24, 0.06),
    Offset(0.48, 0.11),
    Offset(0.74, 0.07),
    Offset(0.92, 0.18),
    Offset(0.12, 0.30),
    Offset(0.36, 0.24),
    Offset(0.62, 0.30),
    Offset(0.88, 0.38),
    Offset(0.07, 0.50),
    Offset(0.27, 0.47),
    Offset(0.51, 0.54),
    Offset(0.76, 0.50),
    Offset(0.95, 0.61),
    Offset(0.16, 0.70),
    Offset(0.40, 0.76),
    Offset(0.65, 0.72),
    Offset(0.86, 0.82),
    Offset(0.10, 0.90),
    Offset(0.31, 0.95),
    Offset(0.56, 0.90),
    Offset(0.80, 0.94),
  ];

  static const _speeds = [
    1.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
    2.0,
    1.0,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = List.generate(_bases.length, (i) {
      final base = _bases[i];
      final phase = i * 0.37;
      final speed = _speeds[i];
      final amp = i.isEven ? 0.018 : 0.026;
      final angle = math.pi * 2 * (t * speed + phase);
      final x = base.dx + math.sin(angle) * amp;
      final y = base.dy + math.cos(angle + phase) * amp * 0.72;

      return Offset(
        x.clamp(0.02, 0.98) * size.width,
        y.clamp(0.02, 0.98) * size.height,
      );
    });

    final threshold = size.shortestSide * 0.28;
    final linePaint = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final distance = (nodes[i] - nodes[j]).distance;
        if (distance > threshold) continue;

        final closeness = 1 - distance / threshold;
        linePaint.color = _accent.withValues(
          alpha: closeness * (isDark ? 0.16 : 0.10),
        );
        canvas.drawLine(nodes[i], nodes[j], linePaint);
      }
    }

    for (var i = 0; i < nodes.length; i++) {
      final pulse =
          (math.sin(math.pi * 2 * (t * _speeds[i] + i * 0.19)) + 1) / 2;
      final radius = 1.4 + pulse * 1.6;
      final node = nodes[i];

      canvas.drawCircle(
        node,
        radius,
        Paint()
          ..color = _accent.withValues(
            alpha: (isDark ? 0.16 : 0.12) + pulse * (isDark ? 0.10 : 0.08),
          ),
      );

      if (i % 5 == 0) {
        final rect = Rect.fromCenter(
          center: node + const Offset(7, -6),
          width: 8,
          height: 2,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1)),
          Paint()..color = _accent.withValues(alpha: isDark ? 0.14 : 0.10),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DigitalParticlesPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.isDark != isDark;
}
