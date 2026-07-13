import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../widgets/document_guide_frame.dart';
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
    final String currentMode = captureModeController.captureMode as String;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Кнопка назад
            GestureDetector(
              onTap: onBack,
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 28,
              ),
            ),

            // кнопка режимов (Авто/Ручн.)
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
                // Иконка фонарика
                GestureDetector(
                  onTap: () async {
                    if (cameraController != null) {
                      bool flashOn =
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

  /// Единая рамка-трафарет листа (затемнение + уголки + подпись) —
  /// показывается и в авто-, и в ручном режиме, как у паспорта/документа.
  Widget _guideFrame(AppLocalizations l10n) {
    return DocumentGuideFrame(
      // Затемнение рисует общий слой камеры (морф между режимами).
      drawScrim: false,
      // Лист A4 портретом: 210/297. Рамка оставляет больше воздуха сверху
      // под статус-карточку и снизу под подпись/селектор режима.
      aspectRatio: 0.71,
      widthFactor: 0.66,
      verticalAlignment: -0.22,
      detected: isDocumentDetected,
      icon: Icons.description_outlined,
      label: isDocumentDetected
          ? l10n.camDocDetectedHint
          : l10n.camFitDocInFrame,
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
          // 2. Рамка-трафарет — в обоих режимах, единый стиль с паспортом.
          _guideFrame(l10n),

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
