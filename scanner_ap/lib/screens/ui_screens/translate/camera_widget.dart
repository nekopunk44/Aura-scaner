import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'apis/recognition_api.dart';
import 'apis/translation_api.dart';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class CameraWidget extends StatefulWidget {
  final CameraDescription camera;

  const CameraWidget({required this.camera, super.key});

  @override
  State<CameraWidget> createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget> {
  late CameraController cameraController;
  late Future<void> initCameraFn;
  String? shownText;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  /// Инициализация камеры
  void _initializeCamera() {
    cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    initCameraFn = cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    }).catchError((error) {
      debugPrint('Ошибка инициализации камеры: $error');
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = false;
      });
    });
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FutureBuilder(
          future: initCameraFn,
          builder: ((context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator.adaptive(),
                    SizedBox(height: 16),
                    Text('Инициализация камеры...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError || !_isCameraInitialized) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.folder_off, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Ошибка камеры',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.hasError ? snapshot.error.toString() : 'Камера не инициализирована',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _initializeCamera();
                      },
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: CameraPreview(cameraController),
            );
          }),
        ),
        Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.center,
            child: FloatingActionButton(
              onPressed: () async {
                try {
                  if (!_isCameraInitialized) return;

                  // индикатор загрузки
                  setState(() {
                    shownText = 'Processing...';
                  });

                  final image = await cameraController.takePicture();
                  final recognizedText = await RecognitionApi.recognizeText(
                    InputImage.fromFile(File(image.path)),
                  );

                  if (recognizedText == null || recognizedText.isEmpty) {
                    setState(() {
                      shownText = 'No text detected';
                    });
                    return;
                  }

                  final translatedText = await TranslationApi.translateText(recognizedText);
                  setState(() {
                    shownText = translatedText;
                  });
                } catch (e) {
                  debugPrint('Ошибка при обработке изображения: $e');
                  setState(() {
                    shownText = 'Error: ${e.toString()}';
                  });
                }
              },
              child: const Icon(Icons.translate),
            ),
          ),
        ),
        if (shownText != null)
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    shownText!,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}