import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../camera_features.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
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
    // Разворот паспорта ~125×88 мм → aspect 1.42, рамка выше центра,
    // чтобы не пересекаться с нижним баром и селектором режимов.
    return DocumentGuideFrame(
      aspectRatio: 1.42,
      widthFactor: 0.85,
      verticalAlignment: -0.42,
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
        _FinishBatchButton(
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

/// Круглая кнопка-галочка «Готово» с бейджем количества страниц.
/// Неактивна (приглушена), пока в буфере нет ни одной страницы.
class _FinishBatchButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _FinishBatchButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: enabled
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF35D07F), Color(0xFF1FA463)],
                    )
                  : null,
              color: enabled ? null : Colors.white.withValues(alpha: 0.07),
              border: Border.all(
                color: Colors.white.withValues(alpha: enabled ? 0.30 : 0.10),
                width: 1.1,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFF26C060).withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              Icons.check_rounded,
              color: enabled ? Colors.white : Colors.white38,
              size: 24,
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
