import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_top_panel.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../l10n/app_localizations.dart';

class UnlimitedDocumentView extends StatelessWidget {
  const UnlimitedDocumentView({
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
    required this.currentBatchPageCount, // Количество страниц в текущей пачке
    required this.onFinishBatch, // Колбэк для завершения пачки
    required this.onClearBatch, // Колбэк для очистки пачки
  });

  // ------------------ Контроллеры и Состояние ------------------
  final CameraController? cameraController;
  final dynamic captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final int currentBatchPageCount; // Неограниченное количество

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

    return CameraControlsBar(
      onCapture: canSnap ? takePicture : null,
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

    final String pageStatus = l10n.pageLabel(currentBatchPageCount + 1);

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Рамку-трафарет рисует общий постоянный слой камеры.

          // 3. Оверлей статуса — от верха экрана (как у паспорта),
          // предсказуемо встаёт над рамкой.
          Positioned.fill(
            child:
                (captureModeController as dynamic).buildStatusOverlay(
                      isDocumentMode: true,
                      pageMode: pageStatus,
                      featureName: "Неограниченный документ",
                      overlayKind: CaptureStatusOverlayKind.batchDocument,
                      l10n: l10n,
                    )
                    as Widget,
          ),

          // 4. Верхняя панель (Переключатель Авто/Ручн.)
          Positioned(top: 0, left: 0, right: 0, child: _buildTopPanel(l10n)),

          // 5. Нижняя панель (Кнопки действий)
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
