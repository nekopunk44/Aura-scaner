import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/camera_controls_bar.dart';
import 'capture_modes.dart';

class RestorePhotoCameraView extends StatelessWidget {
  const RestorePhotoCameraView({
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
    this.photoQuad,
    this.previewAspect,
    this.featureTitle,
    this.featureSubtitle,
    this.overlayKind = CaptureStatusOverlayKind.restorePhoto,
  });

  final CameraController? cameraController;
  final CaptureModeController captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  // Живой контур фото (4 угла, нормализованные 0..1 в координатах сенсора) и
  // соотношение сторон превью для cover-маппинга. Если null — рисуется
  // обычная фиксированная рамка-ориентир.
  final ValueListenable<List<Offset>?>? photoQuad;
  final double? previewAspect;
  final Future<void> Function() takePicture;
  final Future<void> Function() pickImageFromGallery;
  final void Function() setCaptureModeAuto;
  final void Function() setCaptureModeManual;
  final void Function() onBack;
  final void Function() onSettings;
  final String? featureTitle;
  final String? featureSubtitle;
  final CaptureStatusOverlayKind overlayKind;

  Widget _buildTopSegment(String label, bool active, VoidCallback onTap) {
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
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTopSegment(
                    l10n.camAutoLabel,
                    currentMode == 'Автоматически',
                    () {
                      if (currentMode != 'Автоматически') {
                        setCaptureModeAuto();
                      }
                    },
                  ),
                  _buildTopSegment(
                    l10n.camManualLabel,
                    currentMode == 'Вручную',
                    () {
                      if (currentMode != 'Вручную') {
                        setCaptureModeManual();
                      }
                    },
                  ),
                ],
              ),
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

  Widget _buildPhotoFrameOverlay() {
    final quadListenable = photoQuad;
    final aspect = previewAspect;
    // Нет данных для живого контура — обычная фиксированная рамка-ориентир.
    if (quadListenable == null || aspect == null) {
      return _buildStaticFrame();
    }
    return Positioned.fill(
      child: ValueListenableBuilder<List<Offset>?>(
        valueListenable: quadListenable,
        builder: (context, quad, _) {
          if (quad == null || quad.length != 4) {
            return _buildStaticFrame();
          }
          return CustomPaint(
            painter: _PhotoQuadPainter(
              quad: quad,
              contentAspect: aspect,
              active: isDocumentDetected,
            ),
          );
        },
      ),
    );
  }

  // Фиксированная рамка-ориентир: показывается, пока контур фото не найден.
  Widget _buildStaticFrame() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth * 0.85;
        final frameHeight = constraints.maxHeight * 0.55;

        return Align(
          alignment: const Alignment(0, -0.40),
          child: Container(
            width: frameWidth,
            height: frameHeight,
            decoration: BoxDecoration(
              border: Border.all(
                color: isDocumentDetected ? Colors.greenAccent : Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    const isDocumentMode = true;
    final canSnap = captureModeController.canTakePicture(
      isDocumentMode: isDocumentMode,
    );

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
      rightActions: const [],
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
    final isAutoMode = captureModeController.captureMode == 'Автоматически';

    return Stack(
      children: [
        if (isAutoMode) _buildPhotoFrameOverlay(),
        Positioned.fill(
          child: captureModeController.buildStatusOverlay(
            isDocumentMode: true,
            pageMode: featureSubtitle ?? l10n.featRestorePhotoSub,
            featureName: featureTitle ?? l10n.featRestorePhoto,
            overlayKind: overlayKind,
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

/// Рисует живой контур фотографии поверх превью: затемнение вне рамки,
/// саму рамку и угловые точки. Координаты углов — нормализованные (0..1) в
/// пространстве сенсора; здесь они переводятся в экранные с учётом того, что
/// превью рисуется через FittedBox(cover) (кадр обрезан по краям).
class _PhotoQuadPainter extends CustomPainter {
  final List<Offset> quad; // tl, tr, br, bl
  final double contentAspect; // портретное w/h превью
  final bool active;

  const _PhotoQuadPainter({
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

    // Затемнение всего, кроме контура фото.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      path,
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
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
  bool shouldRepaint(covariant _PhotoQuadPainter old) =>
      old.active != active ||
      old.contentAspect != contentAspect ||
      !identical(old.quad, quad);
}
