// id_card_camera_view.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../camera_features.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_mode_switch.dart';
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

            CameraModeSwitch(
              autoLabel: l10n.camAutoLabel,
              manualLabel: l10n.camManualLabel,
              isAuto: currentMode == "Автоматически",
              onAuto: setCaptureModeAuto,
              onManual: setCaptureModeManual,
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

  Widget _buildBottomBar(BuildContext context) {
    const bool isDocumentMode = true;
    final bool canSnap = captureModeController.canTakePicture(isDocumentMode: isDocumentMode);

    return CameraControlsBar(
      onCapture: canSnap ? takePicture : null,
      leftActions: [
        CameraActionIcon(
          icon: Icons.photo_library_outlined,
          onTap: isScanning ? null : pickImageFromGallery,
        ),
      ],
      rightActions: [
        // Отмена: сбрасывает уже снятые стороны (активна, когда лицевая
        // снята и идёт съёмка обратной). Текущая сторона видна в
        // статус-карточке сверху, отдельная пилюля не нужна.
        CameraActionIcon(
          icon: Icons.close_rounded,
          onTap: (currentSide != 'Лицевая' && !isScanning)
              ? resetIdCardState
              : null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cameraController == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      children: [
        // Рамку-трафарет рисует общий постоянный слой камеры.
        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: currentSide,
            featureName: Feat.idCard,
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
