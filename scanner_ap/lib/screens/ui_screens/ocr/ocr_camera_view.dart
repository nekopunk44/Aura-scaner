import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_top_panel.dart';

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
  bool _busy = false;

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
    return CameraTopPanel(
      onBack: widget.onBack,
      cameraController: widget.cameraController,
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

    return Stack(
      children: [
        // Рамку-трафарет (с подписью) рисует общий постоянный слой камеры.

        Positioned(top: 0, left: 0, right: 0, child: _buildTopPanel()),
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      ],
    );
  }
}
