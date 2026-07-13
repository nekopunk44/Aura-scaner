import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../camera_features.dart';
import '../capture_modes.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../widgets/document_guide_frame.dart';
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
    final String currentMode = captureModeController.captureMode as String;

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
              isAuto: currentMode == "Автоматически",
              onAuto: setCaptureModeAuto,
              onManual: setCaptureModeManual,
            ),

            // Фонарик + настройки
            Row(
              children: [
                // Иконка фонарика (предполагается, что родительский виджет обновит FlashMode)
                GestureDetector(
                  onTap: () async {
                    if (cameraController != null) {
                      bool flashOn =
                          cameraController!.value.flashMode == FlashMode.torch;
                      await cameraController!.setFlashMode(
                        flashOn ? FlashMode.off : FlashMode.torch,
                      );
                      // Примечание: Для обновления иконки фонарика родительский виджет
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

  /// Единая рамка-трафарет листа (затемнение + уголки + подпись) — она же
  /// в ручном режиме и как фолбэк в авто, пока живой контур не найден:
  /// оба режима выглядят одинаково.
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

  // Живой контур листа (или рамка-трафарет, пока контур не найден).
  Widget _buildDetectionOverlay(AppLocalizations l10n) {
    final ql = photoQuad;
    final aspect = previewAspect;
    if (ql == null || aspect == null) {
      return _guideFrame(l10n);
    }
    return Positioned.fill(
      child: ValueListenableBuilder<List<Offset>?>(
        valueListenable: ql,
        builder: (context, quad, _) {
          if (quad == null || quad.length != 4) {
            return _guideFrame(l10n);
          }
          return CustomPaint(
            painter: _DocQuadPainter(
              quad: quad,
              contentAspect: aspect,
              active: isDocumentDetected,
            ),
          );
        },
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

    final bool isAutoMode =
        (captureModeController as dynamic).captureMode == 'Автоматически';
    final String pageStatus = currentBatchPageCount < maxPages
        ? l10n.camPageNofM(currentBatchPageCount + 1, maxPages)
        : l10n.camMaxPagesReached(maxPages);

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Авто: живой контур листа (фолбэк — рамка-трафарет).
          // Ручной: та же рамка-трафарет — режимы выглядят одинаково.
          if (isAutoMode) _buildDetectionOverlay(l10n) else _guideFrame(l10n),

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
class _DocQuadPainter extends CustomPainter {
  final List<Offset> quad; // tl, tr, br, bl (нормализованные 0..1)
  final double contentAspect; // портретное w/h превью
  final bool active;

  const _DocQuadPainter({
    required this.quad,
    required this.contentAspect,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double boxAspect = size.width / size.height;
    double dispW, dispH;
    if (boxAspect > contentAspect) {
      dispW = size.width;
      dispH = size.width / contentAspect;
    } else {
      dispH = size.height;
      dispW = size.height * contentAspect;
    }
    final double dx = (size.width - dispW) / 2;
    final double dy = (size.height - dispH) / 2;
    Offset mapPoint(Offset n) => Offset(dx + n.dx * dispW, dy + n.dy * dispH);

    final points = quad.map(mapPoint).toList(growable: false);
    final path = Path()..addPolygon(points, true);

    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      path,
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );

    final Color color = active
        ? const Color(0xFF22C55E)
        : const Color(0xFF2CA5E0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    final dot = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(p, 6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _DocQuadPainter old) =>
      old.active != active ||
      old.contentAspect != contentAspect ||
      !identical(old.quad, quad);
}
