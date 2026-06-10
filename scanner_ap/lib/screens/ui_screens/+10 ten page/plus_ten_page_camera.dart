import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../widgets/camera_controls_bar.dart';


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
    required this.onFinishBatch,        // Колбэк для завершения пачки
    required this.onClearBatch,         // Колбэк для очистки пачки
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

  Widget _buildTopSegment(String label, bool active, Function() onTap) {
    return GestureDetector(
      onTap: onTap as void Function()?,
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
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),

            // кнопка режимов (Авто/Ручн.)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTopSegment("Авто", currentMode == "Автоматически", setCaptureModeAuto),
                  _buildTopSegment("Ручн.", currentMode == "Вручную", setCaptureModeManual),
                ],
              ),
            ),

            // Фонарик + настройки
            Row(
              children: [
                // Иконка фонарика 
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

  Widget _buildDocumentFrameOverlay(double cameraHeightLimit) {
    return LayoutBuilder(
      builder: (context, constraints) {
        
        final double frameWidth = constraints.maxWidth * 0.78;
        
        final double frameHeight = cameraHeightLimit * 0.60;

        // Рамка детекции
        return Align(
          // Центр рамку внутри видоискателя
          alignment: const Alignment(0, -0.15),
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
    final bool canSnap = (captureModeController as dynamic)
        .canTakePicture(isDocumentMode: isDocumentMode) as bool;
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
        GestureDetector(
          onTap: isBatchActive ? onFinishBatch : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              color: isBatchActive
                  ? const Color(0xFF2CA5E0)
                  : Colors.white.withValues(alpha: 0.08),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check,
                  color: isBatchActive ? Colors.white : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Готово ($currentBatchPageCount)',
                  style: TextStyle(
                    fontSize: 13,
                    color: isBatchActive ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
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
          child: CircularProgressIndicator(color: Colors.white));
    }

    final size = MediaQuery.of(context).size;

  
    final double cameraHeightLimit = size.height * 0.85;

    final bool isAutoMode = (captureModeController as dynamic).captureMode == 'Автоматически';
  
    // const int maxPages = 10;
    final String pageStatus = 'Страница ${currentBatchPageCount + 1}'; // Без ограничения

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 2. Рамка детекции
          if (isAutoMode)
            Align(
              alignment: const Alignment(0, -0.75),
              child: SizedBox(
                height: cameraHeightLimit,
                width: size.width,
                child: _buildDocumentFrameOverlay(cameraHeightLimit),
              ),
            ),

          // 3. Оверлей статуса
          Align(
            alignment: const Alignment(0, -0.05),
            child: SizedBox(
              height: cameraHeightLimit,
              width: size.width,
              child: (captureModeController as dynamic).buildStatusOverlay(
                isDocumentMode: true,
                pageMode: pageStatus, // новый статус
                featureName: "Неограниченный документ", 
              ) as Widget,
            ),
          ),

          // 4. Верхняя панель (Переключатель Авто/Ручн.)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopPanel(),
          ),

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