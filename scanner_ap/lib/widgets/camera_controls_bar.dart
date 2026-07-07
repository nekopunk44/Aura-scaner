import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'camera_capture_button.dart';

/// Полупрозрачная панель управления камерой внизу экрана.
/// Capture-кнопка стоит строго по центру (через Align.center в Stack),
/// слева и справа от неё — слоты для action-кнопок (refresh/gallery/sideBtn).
/// Сама панель тянется до низа экрана и сама добавляет SafeArea.bottom
/// в padding, чтобы под жест-баром не было ни видимого зазора, ни
/// перекрытия кнопок системными жестами.
class CameraControlsBar extends StatelessWidget {
  final List<Widget> leftActions;
  final List<Widget> rightActions;
  final VoidCallback? onCapture;
  final bool isBusy;
  final String? captureLabel;

  const CameraControlsBar({
    super.key,
    required this.leftActions,
    required this.rightActions,
    required this.onCapture,
    this.isBusy = false,
    this.captureLabel,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Стеклянный бар: скруглённые верхние углы (низ прижат к краю экрана),
    // blur-подложка + вертикальный градиент затемнения и тонкая световая
    // линия сверху — вместо плоской чёрной плашки.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1,
            ),
          ),
          child: SizedBox(
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _interleaveWithGaps(leftActions),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _interleaveWithGaps(rightActions),
                  ),
                ),
                CameraCaptureButton(
                  onTap: onCapture,
                  isBusy: isBusy,
                  label: captureLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _interleaveWithGaps(List<Widget> items) {
    if (items.isEmpty) return const [];
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) {
        out.add(const SizedBox(width: 18));
      }
    }
    return out;
  }
}

/// Упрощённая панель для инструментов без захвата: только кнопка галереи.
/// Стиль повторяет кнопку галереи экрана «Перевод».
class CameraGalleryBar extends StatelessWidget {
  final VoidCallback? onGallery;

  const CameraGalleryBar({super.key, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final enabled = onGallery != null;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SizedBox(
        height: 78,
        child: Center(
          child: GestureDetector(
            onTap: onGallery,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: enabled ? Colors.white : Colors.white38,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.photo_library,
                color: enabled ? Colors.white : Colors.white38,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Компактная action-кнопка для левого/правого слота панели (refresh,
/// gallery и т.д.). Иконка в круглой полупрозрачной плашке — единый
/// стиль для всех режимов камеры.
class CameraActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  const CameraActionIcon({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: enabled ? 0.14 : 0.07),
          border: Border.all(
            color: Colors.white.withValues(alpha: enabled ? 0.22 : 0.10),
            width: 1.1,
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
          size: 22,
        ),
      ),
    );
  }
}

/// Пилюля «1 → 2» / «Лицевая» — текстовая action-кнопка для правого слота.
class CameraActionPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const CameraActionPill({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          color: Colors.white.withValues(alpha: enabled ? 0.16 : 0.07),
          border: Border.all(
            color: Colors.white.withValues(alpha: enabled ? 0.4 : 0.2),
            width: 1.3,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
