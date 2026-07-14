import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/camera_controls_bar.dart';
import '../../widgets/camera_top_panel.dart';
import '../../widgets/camera_mode_switch.dart';
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

  /// Единая рамка-трафарет (затемнение + уголки + силуэт + подпись) —
  /// как у паспорта: и в авто- (пока контур не найден), и в ручном режиме.
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
        // Найденный quad используется логикой камеры для плавной подстройки
        // общей белой рамки. Отдельный синий контур с точками здесь не рисуем:
        // это выглядело как ручная сетка редактирования в автоматическом режиме.
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
