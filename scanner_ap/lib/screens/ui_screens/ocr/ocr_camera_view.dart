import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/document_guide_frame.dart';
import '../../../l10n/app_localizations.dart';

/// Камера режима OCR. Структура повторяет экран Паспорт: верхняя панель
/// (назад / фонарик / настройки), рамка-видоискатель по центру и нижний
/// бар с кнопкой съёмки и выбором из галереи. После съёмки/выбора
/// изображение уходит на распознавание (колбэки [onCapture]/[onPickGallery]).
class OcrCameraView extends StatefulWidget {
  final CameraController? cameraController;
  final Future<void> Function() onCapture;
  final Future<void> Function() onPickGallery;
  final VoidCallback onBack;
  final VoidCallback onSettings;

  const OcrCameraView({
    super.key,
    required this.cameraController,
    required this.onCapture,
    required this.onPickGallery,
    required this.onBack,
    required this.onSettings,
  });

  @override
  State<OcrCameraView> createState() => _OcrCameraViewState();
}

class _OcrCameraViewState extends State<OcrCameraView> {
  bool _flashOn = false;
  bool _busy = false;

  Future<void> _toggleFlash() async {
    final controller = widget.cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final on = controller.value.flashMode == FlashMode.torch;
      await controller.setFlashMode(on ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _flashOn = !on);
    } catch (e) {
      debugPrint('Ошибка фонарика (OCR): $e');
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildTopPanel() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: widget.onBack,
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: _toggleFlash,
                  child: Icon(
                    _flashOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onSettings,
                  child: const Icon(Icons.settings, color: Colors.white, size: 26),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return CameraControlsBar(
      leftActions: [
        CameraActionIcon(
          icon: Icons.photo_library,
          onTap: _busy ? null : () => _guard(widget.onPickGallery),
        ),
      ],
      rightActions: const [],
      onCapture: _busy ? null : () => _guard(widget.onCapture),
      isBusy: _busy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final l10n = AppLocalizations.of(context);

    return Stack(
      children: [
        // Рамка-трафарет с затемнением и подписью — единый стиль с паспортом.
        DocumentGuideFrame(
          // Затемнение рисует общий слой камеры (морф между режимами).
          drawScrim: false,
          // Текстовый блок — почти квадратный вырез.
          aspectRatio: 0.95,
          widthFactor: 0.78,
          verticalAlignment: -0.22,
          detected: false,
          icon: Icons.text_fields_outlined,
          label: l10n.ocrSelectPhoto,
        ),

        Positioned(top: 0, left: 0, right: 0, child: _buildTopPanel()),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      ],
    );
  }
}
