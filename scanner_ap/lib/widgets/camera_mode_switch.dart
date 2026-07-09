import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Переключатель «Авто / Ручн.» для верхней панели камеры.
///
/// Белая пилюля-тумблер ПЕРЕТЕКАЕТ между сегментами с пружинной кривой
/// (лёгкий overshoot), текст плавно меняет цвет, невыбранный сегмент чуть
/// уменьшен. Единый виджет для всех режимов камеры.
class CameraModeSwitch extends StatelessWidget {
  final String autoLabel;
  final String manualLabel;
  final bool isAuto;
  final VoidCallback onAuto;
  final VoidCallback onManual;

  const CameraModeSwitch({
    super.key,
    required this.autoLabel,
    required this.manualLabel,
    required this.isAuto,
    required this.onAuto,
    required this.onManual,
  });

  void _tap(bool auto) {
    if (auto == isAuto) return;
    HapticFeedback.selectionClick();
    (auto ? onAuto : onManual)();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 172,
      height: 38,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // Скользящая белая пилюля.
            AnimatedAlign(
              alignment:
                  isAuto ? Alignment.centerLeft : Alignment.centerRight,
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutBack,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                _segment(autoLabel, isAuto, () => _tap(true)),
                _segment(manualLabel, !isAuto, () => _tap(false)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedScale(
            scale: active ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.clip),
            ),
          ),
        ),
      ),
    );
  }
}
