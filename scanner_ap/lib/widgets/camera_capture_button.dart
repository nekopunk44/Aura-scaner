import 'package:flutter/material.dart';

/// Кнопка съёмки для камеры: внешнее белое кольцо + внутренний круг,
/// glow-тень акцентного цвета, нажимной shrink-эффект. Дизайн повторяет
/// современные iOS-камеры, но сидит в фирменных цветах приложения.
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

class _CameraCaptureButtonState extends State<CameraCaptureButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.isBusy;
    final size = widget.size;
    final innerSize = size * 0.74;

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.4),
            width: 3,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: const Color(0xFF2CA5E0).withValues(alpha: 0.55),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(5),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _pressed ? 0.82 : 1.0,
          curve: Curves.easeOut,
          child: Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: enabled
                  ? const RadialGradient(
                      colors: [Colors.white, Color(0xFFE8F4FC)],
                      stops: [0.6, 1.0],
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
      ),
    );
  }
}
