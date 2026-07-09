import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../camera_features.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../widgets/document_guide_frame.dart';
import '../../../l10n/app_localizations.dart';

class PassportCameraView extends StatelessWidget {
  const PassportCameraView({
    super.key,
    required this.cameraController,
    required this.captureModeController,
    required this.isDocumentDetected,
    required this.isScanning,
    required this.takePicture,
    required this.pageModeLabel,
    required this.capturedCount,
    required this.onFinishBatch,
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

  /// Сколько страниц уже накоплено в буфере (активирует галочку «Готово»).
  final int capturedCount;

  // ------------------ Функции ------------------
  final Future<void> Function() takePicture;
  final Future<void> Function() onFinishBatch;
  final void Function() resetTwoPageState;
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
            // Кнопка назад
            GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),

            // Сегментированная кнопка режимов
            CameraModeSwitch(
              autoLabel: l10n.camAutoLabel,
              manualLabel: l10n.camManualLabel,
              isAuto: currentMode == "Автоматически",
              onAuto: setCaptureModeAuto,
              onManual: setCaptureModeManual,
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

  Widget _buildDocumentFrameOverlay(AppLocalizations l10n) {
    // Разворот паспорта ~125×88 мм → aspect 1.42. Вертикальное положение
    // совпадает с рамкой ID-карты (-0.25) — единая посадка во всех режимах.
    return DocumentGuideFrame(
      aspectRatio: 1.42,
      widthFactor: 0.85,
      verticalAlignment: -0.25,
      detected: isDocumentDetected,
      icon: Icons.menu_book_outlined,
      label: isDocumentDetected
          ? l10n.camDocDetectedHint
          : l10n.camFitPassportInFrame,
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
        // Галочка «Готово»: активна после первой отсканированной страницы,
        // бейдж показывает сколько страниц уже в буфере.
        CameraFinishButton(
          count: capturedCount,
          onTap: (capturedCount > 0 && !isScanning)
              ? () => onFinishBatch()
              : null,
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

    return Stack(
      children: [
        // Рамка-трафарет показывается всегда — и в авто-, и в ручном режиме.
        _buildDocumentFrameOverlay(AppLocalizations.of(context)),

        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: pageModeLabel,
            featureName: Feat.passport,
            overlayKind: CaptureStatusOverlayKind.passport,
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
