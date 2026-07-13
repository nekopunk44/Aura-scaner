import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/camera_controls_bar.dart';
import '../../widgets/camera_mode_switch.dart';
import '../../widgets/document_guide_frame.dart';
import 'capture_modes.dart';

class RemoveSpotsCameraView extends StatelessWidget {
  const RemoveSpotsCameraView({
    super.key,
    required this.cameraController,
    required this.captureModeController,
    required this.isDocumentDetected,
    required this.isScanning,
    required this.takePicture,
    required this.pickImageFromGallery,
    required this.setCaptureModeAuto,
    required this.setCaptureModeManual,
    required this.onBack,
    required this.onSettings,
  });

  final CameraController? cameraController;
  final CaptureModeController captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final Future<void> Function() takePicture;
  final Future<void> Function() pickImageFromGallery;
  final void Function() setCaptureModeAuto;
  final void Function() setCaptureModeManual;
  final void Function() onBack;
  final void Function() onSettings;


  Widget _buildTopPanel(AppLocalizations l10n) {
    final currentMode = captureModeController.captureMode;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: onBack,
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 28,
              ),
            ),
            CameraModeSwitch(
              autoLabel: l10n.camAutoLabel,
              manualLabel: l10n.camManualLabel,
              isAuto: currentMode == 'Автоматически',
              onAuto: setCaptureModeAuto,
              onManual: setCaptureModeManual,
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (cameraController != null) {
                      final flashOn =
                          cameraController!.value.flashMode == FlashMode.torch;
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
                  child: const Icon(
                    Icons.settings,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Единая рамка-трафарет (затемнение + уголки + силуэт + подпись) —
  /// как у паспорта: и в авто-, и в ручном режиме.
  Widget _guideFrame(AppLocalizations l10n) {
    return DocumentGuideFrame(
      // Затемнение рисует общий слой камеры (морф между режимами).
      drawScrim: false,
      // Портретное фото ~3:4.
      aspectRatio: 0.75,
      widthFactor: 0.72,
      verticalAlignment: -0.22,
      detected: isDocumentDetected,
      icon: Icons.cleaning_services_outlined,
      label: isDocumentDetected
          ? l10n.camDocDetectedHint
          : l10n.camFitPhotoInFrame,
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return CameraControlsBar(
      leftActions: [
        CameraActionIcon(
          icon: Icons.photo_library,
          onTap: isScanning ? null : pickImageFromGallery,
        ),
      ],
      rightActions: const [],
      onCapture: isScanning ? null : takePicture,
      isBusy: isScanning,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final l10n = AppLocalizations.of(context);

    return Stack(
      children: [
        // Рамка-трафарет — в обоих режимах, как у паспорта.
        _guideFrame(l10n),
        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: l10n.featRemoveSpotsSub,
            featureName: l10n.featRemoveSpots,
            overlayKind: CaptureStatusOverlayKind.removeSpots,
            l10n: l10n,
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _buildTopPanel(l10n)),
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
