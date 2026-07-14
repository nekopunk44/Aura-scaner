import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../camera_features.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_top_panel.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../l10n/app_localizations.dart';

class MultiPageDocumentView extends StatelessWidget {
  const MultiPageDocumentView({
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
    required this.maxPages,
    required this.currentBatchPageCount,
    required this.onFinishBatch,
    required this.onClearBatch,
    this.photoQuad,
    this.previewAspect,
  });

  // ------------------ Контроллеры и Состояние ------------------
  final CameraController? cameraController;
  final dynamic captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final int maxPages;
  final int currentBatchPageCount; // 0-maxPages

  // Живой контур листа (4 нормализованных угла) + соотношение сторон превью.
  final ValueListenable<List<Offset>?>? photoQuad;
  final double? previewAspect;

  // ------------------ Функции ------------------
  final Future<void> Function() takePicture;
  final Future<void> Function() pickImageFromGallery;
  final void Function() setCaptureModeAuto;
  final void Function() setCaptureModeManual;
  final void Function() onBack;
  final void Function() onSettings;
  final void Function() onFinishBatch;
  final void Function() onClearBatch;

  // ------------------------------------------------------------
  // Вспомогательные UI методы
  // ------------------------------------------------------------

  Widget _buildTopPanel(AppLocalizations l10n) {
    return CameraTopPanel(
      onBack: onBack,
      cameraController: cameraController,
      modeSwitch: CameraModeSwitch(
        autoLabel: l10n.camAutoLabel,
        manualLabel: l10n.camManualLabel,
        isAuto: captureModeController.captureMode == 'Автоматически',
        onAuto: setCaptureModeAuto,
        onManual: setCaptureModeManual,
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    const bool isDocumentMode = true;

    final bool canSnap =
        (captureModeController as dynamic).canTakePicture(
              isDocumentMode: isDocumentMode,
            )
            as bool;

    final bool isBatchActive = currentBatchPageCount > 0;
    final bool canAddMore = currentBatchPageCount < maxPages;
    final bool captureButtonActive = canSnap && canAddMore;

    return CameraControlsBar(
      onCapture: captureButtonActive ? takePicture : null,
      captureLabel: '${currentBatchPageCount + 1}',
      leftActions: [
        CameraActionIcon(
          icon: Icons.delete_outline,
          onTap: isBatchActive ? onClearBatch : null,
        ),
        CameraActionIcon(
          icon: Icons.photo_library_outlined,
          onTap: pickImageFromGallery,
        ),
      ],
      rightActions: [
        // Галочка «Готово» с бейджем количества — единый стиль с паспортом.
        CameraFinishButton(
          count: currentBatchPageCount,
          onTap: isBatchActive ? onFinishBatch : null,
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // UI — основное окно камеры
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final l10n = AppLocalizations.of(context);

    final String pageStatus = currentBatchPageCount < maxPages
        ? l10n.camPageNofM(currentBatchPageCount + 1, maxPages)
        : l10n.camMaxPagesReached(maxPages);

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Статус-карточка позиционируется от верха экрана (как у паспорта),
          // а не от смещённого бокса — предсказуемо встаёт над рамкой.
          Positioned.fill(
            child:
                (captureModeController as dynamic).buildStatusOverlay(
                      isDocumentMode: true,
                      pageMode: pageStatus,
                      featureName: Feat.document,
                      overlayKind: CaptureStatusOverlayKind.document,
                      l10n: l10n,
                    )
                    as Widget,
          ),

          Positioned(top: 0, left: 0, right: 0, child: _buildTopPanel(l10n)),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context),
          ),
        ],
      ),
    );
  }
}

/// Рисует живой контур листа поверх превью (cover-маппинг по previewAspect):
/// затемнение вне контура, сам контур и угловые точки. Зелёный — когда лист
/// стабильно распознан (вот-вот автоснимок), синий — пока ловится.
