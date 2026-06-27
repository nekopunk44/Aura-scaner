// id_card_camera_view.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../l10n/app_localizations.dart';

class IdCardCameraView extends StatelessWidget {
  const IdCardCameraView({
    super.key,
    required this.cameraController,
    required this.captureModeController,
    required this.isDocumentDetected,
    required this.isScanning,
    required this.takePicture,
    required this.currentSide,
    required this.resetIdCardState,
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
  final String currentSide;

  // ------------------ Функции ------------------
  final Future<void> Function() takePicture;
  final void Function() resetIdCardState;
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

  Widget _buildTopPanel(AppLocalizations l10n) {
    final String currentMode = captureModeController.captureMode;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),

            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTopSegment(l10n.camAutoLabel, currentMode == "Автоматически", () {
                    if (currentMode != "Автоматически") {
                      setCaptureModeAuto();
                    }
                  }),
                  _buildTopSegment(l10n.camManualLabel, currentMode == "Вручную", () {
                    if (currentMode != "Вручную") {
                      setCaptureModeManual();
                    }
                  }),
                ],
              ),
            ),

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
        // ширина рамки
        final double frameWidth = constraints.maxWidth * 0.85;

        const double aspectRatio = 1.6;
        final double frameHeight = frameWidth / aspectRatio; // Высота = Ширина / 1.6

        return Align(
          alignment: const Alignment(0, -0.16),
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
    final bool canSnap = captureModeController.canTakePicture(isDocumentMode: isDocumentMode);

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
          label: currentSide == 'Лицевая'
              ? AppLocalizations.of(context).camIdFront
              : AppLocalizations.of(context).camIdBack,
          onTap: null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    final bool isAutoMode = captureModeController.captureMode == 'Автоматически';

    return Stack(
      children: [
        if (isAutoMode)
          _buildDocumentFrameOverlay(),

        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: currentSide,
            featureName: "Удостоверение личности",
            overlayKind: CaptureStatusOverlayKind.idCard,
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopPanel(AppLocalizations.of(context)),
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
