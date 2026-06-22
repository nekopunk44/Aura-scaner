import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'capture_modes.dart';
import 'restore_photo_camera_view.dart';

class RemoveWatermarkCameraView extends StatelessWidget {
  const RemoveWatermarkCameraView({
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
  });

  final CameraController? cameraController;
  final CaptureModeController captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final ValueListenable<List<Offset>?>? photoQuad;
  final double? previewAspect;
  final Future<void> Function() takePicture;
  final Future<void> Function() pickImageFromGallery;
  final void Function() setCaptureModeAuto;
  final void Function() setCaptureModeManual;
  final void Function() onBack;
  final void Function() onSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RestorePhotoCameraView(
      cameraController: cameraController,
      captureModeController: captureModeController,
      isDocumentDetected: isDocumentDetected,
      isScanning: isScanning,
      photoQuad: photoQuad,
      previewAspect: previewAspect,
      takePicture: takePicture,
      pickImageFromGallery: pickImageFromGallery,
      setCaptureModeAuto: setCaptureModeAuto,
      setCaptureModeManual: setCaptureModeManual,
      onBack: onBack,
      onSettings: onSettings,
      featureTitle: l10n.featRemoveWatermark,
      featureSubtitle: l10n.featRemoveWatermarkSub,
      overlayKind: CaptureStatusOverlayKind.removeWatermark,
    );
  }
}
