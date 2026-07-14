import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'camera_capture_button.dart';

/// Полупрозрачная панель управления камерой внизу экрана.
/// Capture-кнопка стоит строго по центру (через Align.center в Stack),
/// слева и справа от неё — слоты для action-кнопок (refresh/gallery/sideBtn).
/// Сама панель тянется до низа экрана и сама добавляет SafeArea.bottom
/// в padding, чтобы под жест-баром не было ни видимого зазора, ни
/// перекрытия кнопок системными жестами.
class CameraControlsBar extends StatefulWidget {
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

  /// Registers the translation bar, which has its own language control but
  /// shares the gallery action with the standard camera bar. Returns the
  /// gallery slot used by the preceding filter so translation can animate it.
  static int registerGalleryOnlyLayout() {
    final previousGallery = _CameraControlsBarState._previousLeftIds.indexOf(
      'gallery',
    );
    _CameraControlsBarState._previousLeftIds = const ['gallery'];
    _CameraControlsBarState._previousRightIds = const [];
    return previousGallery;
  }

  @override
  State<CameraControlsBar> createState() => _CameraControlsBarState();
}

class _CameraControlsBarState extends State<CameraControlsBar>
    with SingleTickerProviderStateMixin {
  static List<String> _previousLeftIds = const [];
  static List<String> _previousRightIds = const [];

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  late final List<String> _fromLeftIds;
  late final List<String> _fromRightIds;

  @override
  void initState() {
    super.initState();
    _fromLeftIds = List<String>.from(_previousLeftIds);
    _fromRightIds = List<String>.from(_previousRightIds);
    _previousLeftIds = widget.leftActions.map(_actionId).toList();
    _previousRightIds = widget.rightActions.map(_actionId).toList();
    _transition.forward();
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    // Стеклянный бар: скруглённые верхние углы (низ прижат к краю экрана),
    // blur-подложка + вертикальный градиент затемнения и тонкая световая
    // линия сверху — вместо плоской чёрной плашки.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        // Sigma умеренная: blur считается на каждом кадре превью камеры.
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                    children: _animatedActions(
                      widget.leftActions,
                      _fromLeftIds,
                      fromRight: false,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _animatedActions(
                      widget.rightActions,
                      _fromRightIds,
                      fromRight: true,
                    ),
                  ),
                ),
                CameraCaptureButton(
                  onTap: widget.onCapture,
                  isBusy: widget.isBusy,
                  label: widget.captureLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _animatedActions(
    List<Widget> items,
    List<String> previousIds, {
    required bool fromRight,
  }) {
    if (items.isEmpty) return const [];
    final out = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      final child = items[i];
      final id = _actionId(child);
      final previousIndex = previousIds.indexOf(id);
      final isExisting = previousIndex >= 0;
      final slotDelta = isExisting ? previousIndex - i : 0;
      out.add(
        AnimatedBuilder(
          animation: _transition,
          child: child,
          builder: (context, child) {
            final t = Curves.easeInOutCubic.transform(_transition.value);
            final direction = fromRight ? -1.0 : 1.0;
            final dx = slotDelta * 64.0 * direction * (1 - t);
            final opacity = isExisting ? 1.0 : t;
            final scale = isExisting ? 1.0 : 0.82 + 0.18 * t;
            return Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Transform.scale(scale: scale, child: child),
              ),
            );
          },
        ),
      );
      if (i != items.length - 1) {
        out.add(const SizedBox(width: 18));
      }
    }
    return out;
  }

  static String _actionId(Widget action) {
    if (action is CameraActionIcon) {
      final icon = action.icon;
      if (icon == Icons.photo_library ||
          icon == Icons.photo_library_outlined ||
          icon == Icons.photo_outlined) {
        return 'gallery';
      }
      if (icon == Icons.delete || icon == Icons.delete_outline) {
        return 'delete';
      }
      return 'icon:${icon.codePoint}';
    }
    if (action is CameraFinishButton) return 'finish';
    if (action is CameraActionPill) return 'pill:${action.label}';
    return '${action.runtimeType}:${action.key}';
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
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                Icons.photo_outlined,
                color: enabled ? Colors.white : Colors.white38,
                size: 30,
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
    final displayIcon = icon == Icons.photo_library
        ? Icons.photo_outlined
        : icon;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          displayIcon,
          color: enabled
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.white30,
          size: 28,
        ),
      ),
    );
  }
}

/// Круглая кнопка-галочка «Готово» с бейджем количества страниц.
/// Неактивна (приглушена), пока в буфере нет ни одной страницы.
/// Единый стиль для паспорта, документа и «+10 страниц».
class CameraFinishButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const CameraFinishButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              Icons.check_rounded,
              color: enabled
                  ? Colors.white.withValues(alpha: 0.92)
                  : Colors.white30,
              size: 28,
            ),
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF2CA5E0),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Пилюля «1 → 2» / «Лицевая» — текстовая action-кнопка для правого слота.
class CameraActionPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const CameraActionPill({super.key, required this.label, required this.onTap});

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
