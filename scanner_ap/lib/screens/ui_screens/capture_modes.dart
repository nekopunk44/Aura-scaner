import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Контроллер режимов съёмки документов.
///
/// Управляет двумя режимами:
/// - **Автоматически** — ждёт 3 секунды после обнаружения документа, затем
///   разрешает съёмку. Показывает анимацию рамки при детекции.
/// - **Вручную** — съёмка доступна в любой момент без ожидания.
///
/// Используется во всех модулях камеры: документы, паспорт, ID-карта.
class CaptureModeController {
 

  String captureMode = 'Автоматически';
  bool isDocumentDetected = false;
  bool isScanning = false;
  Timer? detectionTimer;

  void resetDetectionState() {
    detectionTimer?.cancel();
    detectionTimer = null;
    isDocumentDetected = false;
  }

  void startDetectionStream({
    required bool isDocumentMode,
    required Function(bool detected) onDetectionChanged,
    required AnimationController animationController,
  }) {
    resetDetectionState();
    onDetectionChanged(false);
    animationController.reverse(from: animationController.value);

    if (captureMode == 'Автоматически' && isDocumentMode) {
      detectionTimer = Timer(const Duration(seconds: 3), () {
        if (captureMode == 'Автоматически') {
          isDocumentDetected = true;
          animationController.forward(from: 0.0);
          onDetectionChanged(true);
        }
      });
    }
  }

  bool canTakePicture({
    required bool isDocumentMode,
  }) {
    if (isScanning) return false;

    if (captureMode == 'Автоматически' &&
        isDocumentMode &&
        !isDocumentDetected) {
      return false;
    }

    return true;
  }

  void setCaptureMode(String mode) {
    captureMode = mode;
    if (mode == 'Вручную') {
      resetDetectionState();
    }
  }

  Widget buildStatusOverlay({
    required bool isDocumentMode,
    required String pageMode,
    required String featureName,
    AppLocalizations? l10n,
  }) {
    if (!isDocumentMode || captureMode == 'Вручную') {
      return const SizedBox.shrink();
    }

    String text;
    Color color;

    if (isScanning) {
      text = l10n?.camProcessing ?? 'Обработка...';
      color = Colors.amber;
    } else if (isDocumentDetected) {
      return const SizedBox.shrink();
    } else {
      if (featureName == '+100 страниц' || featureName == 'Пакетный Документ') {
        text = l10n?.camWaitingDocBatch(pageMode) ?? 'Ожидание документа $pageMode';
      } else {
        text = l10n?.camWaitingDocMode(featureName, pageMode) ?? 'Ожидание документа ($featureName — $pageMode)';
      }

      color = Colors.white;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20)),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}