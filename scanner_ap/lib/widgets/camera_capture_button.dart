import 'package:flutter/material.dart';

class CameraCaptureButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;
  final bool isBusy;
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.18),
                border: Border.all(
                  color: enabled
                      ? const Color(0xFF38BDF8)
                      : Colors.white.withValues(alpha: 0.25),
                  width: 3,
                ),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF2CA5E0,
                          ).withValues(alpha: 0.22),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 140),
              scale: _pressed ? 0.84 : 1,
              curve: Curves.easeOut,
              child: Container(
                width: size * 0.74,
                height: size * 0.74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: enabled
                      ? const Color(0xFFF7FAFC)
                      : Colors.white.withValues(alpha: 0.22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.2),
                  ),
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
