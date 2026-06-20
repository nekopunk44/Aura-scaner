import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';

class PassportCameraView extends StatelessWidget {
  const PassportCameraView({
    super.key,
    required this.cameraController,
    required this.captureModeController,
    required this.isDocumentDetected,
    required this.isScanning,
    required this.takePicture,
    required this.pageModeLabel,
    required this.pageCount,
    required this.setPageCount,
    required this.resetTwoPageState,
    required this.pickImageFromGallery,
    required this.setCaptureModeAuto,
    required this.setCaptureModeManual,
    required this.onBack,
    required this.onSettings,
  });

  // ------------------ Контроллеры и Состояние ------------------
  final CameraController? cameraController;
  final CaptureModeController captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final String pageModeLabel;
  final int pageCount;

  // ------------------ Функции ------------------
  final Future<void> Function() takePicture;
  final void Function(int count) setPageCount;
  final void Function() resetTwoPageState;
  final Future<void> Function() pickImageFromGallery;
  final void Function() setCaptureModeAuto; 
  final void Function() setCaptureModeManual; 
  final void Function() onBack;
  final void Function() onSettings;

 
  Widget _buildTopSegment(String label, bool active, Function() onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTopPanel() {
    final String currentMode = captureModeController.captureMode;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Кнопка назад
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),

            // Сегментированная кнопка режимов
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTopSegment("Авто", currentMode == "Автоматически", () {
                    if (currentMode != "Автоматически") {
                      setCaptureModeAuto(); 
                    }
                  }),
                  _buildTopSegment("Ручн.", currentMode == "Вручную", () {
                    if (currentMode != "Вручную") {
                      setCaptureModeManual();
                    }
                  }),
                ],
              ),
            ),

            // Фонарик + настройки
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (cameraController != null) {
                      bool flashOn = cameraController!.value.flashMode == FlashMode.torch;

                      await cameraController!.setFlashMode(
                        flashOn ? FlashMode.off : FlashMode.torch,
                      );
                    }
                  },
                  child: Icon(
                    cameraController?.value.flashMode == FlashMode.torch
                        ? Icons.flash_on
                        : Icons.flash_off,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onSettings,
                  child: const Icon(Icons.settings, color: Colors.white, size: 26),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentFrameOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double frameWidth = constraints.maxWidth * 0.85;
        final double frameHeight = constraints.maxHeight * 0.55;

        // Рамка
        return Align(
          alignment: const Alignment(0, -0.40), 
          child: Container(
            width: frameWidth,
            height: frameHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: isDocumentDetected ? Colors.greenAccent : Colors.white,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    const bool isDocumentMode = true;
    final bool canSnap =
        captureModeController.canTakePicture(isDocumentMode: isDocumentMode);

    return CameraControlsBar(
      onCapture: canSnap ? takePicture : null,
      leftActions: [
        CameraActionIcon(
          icon: Icons.refresh,
          onTap: isScanning ? null : setCaptureModeAuto,
        ),
        CameraActionIcon(
          icon: Icons.photo_library_outlined,
          onTap: isScanning ? null : pickImageFromGallery,
        ),
      ],
      rightActions: [
        CameraActionPill(
          label: '$pageCount стр.',
          onTap: () async {
            final selectedCount = await showModalBottomSheet<int>(
              context: context,
              backgroundColor: const Color(0xFF111111),
              builder: (sheetContext) {
                return SafeArea(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: 10,
                    itemBuilder: (context, index) {
                      final count = index + 1;
                      final isSelected = count == pageCount;
                      return ListTile(
                        title: Text(
                          '$count стр.',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF2CA5E0) : Colors.white,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF2CA5E0))
                            : null,
                        onTap: () => Navigator.pop(sheetContext, count),
                      );
                    },
                  ),
                );
              },
            );

            if (selectedCount == null || selectedCount == pageCount) return;
            setPageCount(selectedCount);
            resetTwoPageState();
            setCaptureModeAuto();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    final bool isAutoMode = captureModeController.captureMode == 'Автоматически';

    return Stack(
      children: [
        if (isAutoMode)
          _buildDocumentFrameOverlay(),

        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: pageModeLabel,
            featureName: "Паспорт",
            overlayKind: CaptureStatusOverlayKind.passport,
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopPanel(),
        ),

        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildBottomBar(context),
        ),
      ],
    );
  }
}
