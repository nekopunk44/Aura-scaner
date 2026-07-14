import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Верхняя панель камеры: стрелка «назад» слева, переключатель Авто/Ручн.
/// СТРОГО по центру (через Stack — не зависит от ширины боковых кнопок)
/// и кнопка фонарика справа. Кнопки настроек нет — только фонарик.
class CameraTopPanel extends StatelessWidget {
  final VoidCallback onBack;
  final CameraController? cameraController;

  /// Переключатель Авто/Ручн. (null — режим без него, например OCR/QR).
  final Widget? modeSwitch;

  const CameraTopPanel({
    super.key,
    required this.onBack,
    required this.cameraController,
    this.modeSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: onBack,
                  child: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              if (modeSwitch != null) Center(child: modeSwitch),
              Align(
                alignment: Alignment.centerRight,
                child: CameraFlashButton(cameraController: cameraController),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Кнопка фонарика с «живой» анимацией нажатия: проседает при тапе,
/// при включении заливается тёплым светом со свечением, иконка меняется
/// с поворотом и растворением.
class CameraFlashButton extends StatefulWidget {
  final CameraController? cameraController;

  const CameraFlashButton({super.key, required this.cameraController});

  @override
  State<CameraFlashButton> createState() => _CameraFlashButtonState();
}

class _CameraFlashButtonState extends State<CameraFlashButton> {
  bool _pressed = false;
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _on = widget.cameraController?.value.flashMode == FlashMode.torch;
  }

  @override
  void didUpdateWidget(CameraFlashButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraController != widget.cameraController) {
      _on = widget.cameraController?.value.flashMode == FlashMode.torch;
    }
  }

  Future<void> _toggle() async {
    final controller = widget.cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    HapticFeedback.selectionClick();
    try {
      final on = controller.value.flashMode == FlashMode.torch;
      await controller.setFlashMode(on ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _on = !on);
    } catch (e) {
      debugPrint('Ошибка фонарика: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: _toggle,
      // В покое — обычная белая иконка, как остальные элементы панели
      // (без плашки). «Кнопочность» видна только в момент нажатия
      // (проседание) и во включённом состоянии (тёплое свечение).
      child: AnimatedScale(
        scale: _pressed ? 0.78 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _on
                ? const Color(0xFFFFC107).withValues(alpha: 0.16)
                : Colors.transparent,
            boxShadow: _on
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFC107).withValues(alpha: 0.45),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, animation) => RotationTransition(
              turns: Tween<double>(begin: 0.85, end: 1).animate(animation),
              child: ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
            ),
            child: Icon(
              _on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              key: ValueKey<bool>(_on),
              color: _on ? const Color(0xFFFFD54F) : Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
