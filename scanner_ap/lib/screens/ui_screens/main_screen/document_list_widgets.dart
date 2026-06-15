import 'package:flutter/material.dart';

/// Пункт действия в bottom-sheet (переименовать / поделиться / удалить …).
class SheetAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color textColor;
  final VoidCallback onTap;

  const SheetAction({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label,
          style: TextStyle(
              color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

/// Анимированная строка-скелет для состояния загрузки списка документов.
class SkeletonRow extends StatefulWidget {
  final Color baseColor;
  final Color highlightColor;
  const SkeletonRow({super.key, required this.baseColor, required this.highlightColor});

  @override
  State<SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final color = Color.lerp(widget.baseColor, widget.highlightColor, (t < 0.5 ? t : 1 - t) * 2)!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: widget.highlightColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12, width: double.infinity,
                      decoration: BoxDecoration(
                        color: widget.highlightColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10, width: 120,
                      decoration: BoxDecoration(
                        color: widget.highlightColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
