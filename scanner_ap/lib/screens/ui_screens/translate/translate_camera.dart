import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:io';

import 'apis/recognition_api.dart';
import 'apis/translation_api.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

class TranslateCamera extends StatefulWidget {
  final CameraController? cameraController;
  final Future<XFile?> Function() takePicture;
  final Function pickImageFromGallery;
  final Function onBack;
  final Function onSettings;
  final Function(String)? onScanCompleted;

  final dynamic captureModeController;
  final bool isDocumentDetected;
  final bool isScanning;
  final Function setCaptureModeAuto;
  final Function setCaptureModeManual;

  const TranslateCamera({
    super.key,
    required this.cameraController,
    required this.takePicture,
    required this.pickImageFromGallery,
    required this.onBack,
    required this.onSettings,
    this.onScanCompleted,
    required this.captureModeController,
    required this.isDocumentDetected,
    required this.isScanning,
    required this.setCaptureModeAuto,
    required this.setCaptureModeManual,
  });

  @override
  State<TranslateCamera> createState() => _TranslateCameraState();
}

class _TranslateCameraState extends State<TranslateCamera> {
  String? _shownText;
  bool _isProcessing = false;

  Future<void> _translateImage() async {
    if (widget.cameraController == null ||
        !widget.cameraController!.value.isInitialized ||
        _isProcessing) {
      return;
    }

    try {
      setState(() {
        _isProcessing = true;
        _shownText = 'Обработка...';
      });

      final XFile? imageFile = await widget.takePicture();

      if (imageFile == null) {
        setState(() {
          _shownText = 'Ошибка при съемке';
          _isProcessing = false;
        });
        return;
      }

      final recognizedText = await RecognitionApi.recognizeText(
        InputImage.fromFile(File(imageFile.path)),
      );

      if (recognizedText == null || recognizedText.isEmpty) {
        setState(() {
          _shownText = 'Текст не обнаружен';
          _isProcessing = false;
        });
        return;
      }

      debugPrint('Распознанный текст: $recognizedText');

      final translatedText = await TranslationApi.translateText(recognizedText);

      setState(() {
        _shownText = translatedText ?? 'Ошибка перевода';
        _isProcessing = false;
      });

      if (widget.onScanCompleted != null && translatedText != null) {
        widget.onScanCompleted!(translatedText);
      }

    } catch (e) {
      debugPrint('Ошибка при переводе: $e');
      if (!mounted) return;
      setState(() {
        _shownText = 'Ошибка: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickImageAndTranslate() async {
    try {
      setState(() {
        _isProcessing = true;
        _shownText = 'Обработка...';
      });

      final ImagePicker picker = ImagePicker();
      final XFile? galleryImage = await picker.pickImage(source: ImageSource.gallery);

      if (!mounted) return;
      if (galleryImage == null) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final recognizedText = await RecognitionApi.recognizeText(
        InputImage.fromFile(File(galleryImage.path)),
      );

      if (!mounted) return;
      if (recognizedText == null || recognizedText.isEmpty) {
        setState(() {
          _shownText = 'Текст не обнаружен';
          _isProcessing = false;
        });
        return;
      }

      final translatedText = await TranslationApi.translateText(recognizedText);

      if (!mounted) return;
      setState(() {
        _shownText = translatedText ?? 'Ошибка перевода';
        _isProcessing = false;
      });

      if (widget.onScanCompleted != null && translatedText != null) {
        widget.onScanCompleted!(translatedText);
      }

    } catch (e) {
      debugPrint('Ошибка при выборе из галереи: $e');
      if (!mounted) return;
      setState(() {
        _shownText = 'Ошибка при выборе изображения';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Кнопка Назад
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => widget.onBack(),
            ),
          ),

          // Инструкция
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Режим перевода',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Наведите камеру на текст и нажмите кнопку перевода',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_isProcessing)
                    const CircularProgressIndicator(color: Colors.white),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            left: 30,
            child: GestureDetector(
              onTap: _isProcessing ? null : _pickImageAndTranslate,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _isProcessing ? Colors.grey : Colors.white,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.photo_library,
                    color: _isProcessing ? Colors.grey : Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.center,
              child: FloatingActionButton(
                onPressed: _isProcessing ? null : _translateImage,
                backgroundColor: _isProcessing ? Colors.grey : Colors.blue,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.translate, size: 30),
              ),
            ),
          ),

          if (_shownText != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Перевод:',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _shownText!,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () => setState(() => _shownText = null),
                              child: const Text('Закрыть'),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                if (_shownText != null) {
                                  Clipboard.setData(ClipboardData(text: _shownText!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Текст скопирован'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Копировать'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}