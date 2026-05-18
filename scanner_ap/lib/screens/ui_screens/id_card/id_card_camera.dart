// id_card_camera_view.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../capture_modes.dart';

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

  Widget _buildTopPanel() {
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
    final bool canSnap = captureModeController.canTakePicture(isDocumentMode: isDocumentMode);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: isScanning ? null : setCaptureModeAuto,
            child: const Icon(Icons.refresh, color: Colors.white, size: 30),
          ),

          GestureDetector(
            onTap: isScanning ? null : pickImageFromGallery,
            child: const Icon(Icons.photo_library, color: Colors.white, size: 30),
          ),

          GestureDetector(
            onTap: canSnap ? takePicture : null,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: canSnap ? Colors.white : Colors.grey, width: 4),
                color: canSnap ? Colors.white : Colors.transparent,
              ),
              child: canSnap
                  ? Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              )
                  : const SizedBox.shrink(),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white70, width: 1.6),
              color: Colors.black45,
            ),
            child: Text(
              currentSide,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
        Positioned.fill(
          child: CameraPreview(cameraController!),
        ),

        if (isAutoMode)
          _buildDocumentFrameOverlay(),

        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: currentSide,
            featureName: "Удостоверение личности",
          ),
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopPanel(),
        ),

        Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 0,
          right: 0,
          child: _buildBottomBar(context),
        ),
      ],
    );
  }
}