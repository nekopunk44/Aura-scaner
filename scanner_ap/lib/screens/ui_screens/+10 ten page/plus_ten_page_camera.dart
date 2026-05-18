import 'package:flutter/material.dart';
import 'package:camera/camera.dart';


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
    
    // const int maxPages = 9; // Исходное ограничение
    const bool isDocumentMode = true;

    
    final bool canSnap = (captureModeController as dynamic).canTakePicture(isDocumentMode: isDocumentMode) as bool;

    final bool isBatchActive = currentBatchPageCount > 0;

    final bool captureButtonActive = canSnap; 

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      color: Colors.black, 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Кнопка Очистить пачку
          GestureDetector(
            onTap: isBatchActive ? onClearBatch : null,
            child: Icon(
              Icons.delete_forever,
              color: isBatchActive ? Colors.redAccent : Colors.grey,
              size: 30,
            ),
          ),

          // 2. Кнопка Галереи (для добавления страницы из галереи)
          GestureDetector(
            onTap: pickImageFromGallery,
            child: const Icon(Icons.photo_library, color: Colors.white, size: 30),
          ),

          // 3. Кнопка снимка (Добавить страницу) - с индикатором номера страницы
          GestureDetector(
            onTap: captureButtonActive ? takePicture : null,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: captureButtonActive ? Colors.white : Colors.grey, width: 4),
                color: Colors.transparent,
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: captureButtonActive ? Colors.white : Colors.grey[600],
                  ),
                  child: Center(
                    child: Text(
                      '${currentBatchPageCount + 1}', // Показ номера следующей страницы
                      style: TextStyle(
                        color: captureButtonActive ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 4. Кнопка Готово (Завершить пачку)
          GestureDetector(
            onTap: isBatchActive ? onFinishBatch : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: isBatchActive ? Colors.green : Colors.grey[700],
              ),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.white, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Готово ($currentBatchPageCount)',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

    // 2. Логика отображения CameraPreview с обрезкой
    final cameraFullHeight = size.width / cameraController!.value.aspectRatio;

    final limitedCameraPreview = ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: size.width,
            height: cameraFullHeight,
            child: CameraPreview(cameraController!),
          ),
        ),
      ),
    );

    return Container(
      color: Colors.black, // Весь фон - черный
      child: Stack(
        children: [
          // 1. Ограниченный видоискатель
          Align(
            
            alignment: const Alignment(0, -0.85),
            child: SizedBox(
              height: cameraHeightLimit, // ограничение высоты
              width: size.width,
              child: limitedCameraPreview,
            ),
          ),

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
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              child: _buildBottomBar(context),
            ),
          ),
        ],
      ),
    );
  }
}