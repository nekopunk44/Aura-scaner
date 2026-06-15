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

  /// Целевой язык перевода. Источник определяется автоматически в
  /// TranslationApi, а цель выбирает пользователь. По умолчанию — русский.
  String _targetLang = 'ru';

  /// Состояние фонарика (для иконки). Сам фонарик — через CameraController.
  bool _flashOn = false;

  Future<void> _toggleFlash() async {
    final controller = widget.cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final on = controller.value.flashMode == FlashMode.torch;
      await controller.setFlashMode(on ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _flashOn = !on);
    } catch (e) {
      debugPrint('Ошибка фонарика (перевод): $e');
    }
  }

  /// Поддерживаемые целевые языки (коды совпадают с _mapLanguageCode в
  /// TranslationApi). Названия — на родном языке, переводить их не нужно.
  static const Map<String, String> _languages = {
    'ru': 'Русский',
    'en': 'English',
    'es': 'Español',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'pt': 'Português',
    'pl': 'Polski',
    'tr': 'Türkçe',
    'ar': 'العربية',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
  };

  void _showLanguagePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E2A3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Перевести на',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _languages.entries.map((e) {
                    final selected = e.key == _targetLang;
                    return ListTile(
                      title: Text(
                        e.value,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF2CA5E0)
                              : Colors.white,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check, color: Color(0xFF2CA5E0))
                          : null,
                      onTap: () {
                        setState(() => _targetLang = e.key);
                        Navigator.pop(sheetContext);
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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

      final translatedText = await TranslationApi.translateText(
        recognizedText,
        targetLanguage: _targetLang,
      );

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

      final translatedText = await TranslationApi.translateText(
        recognizedText,
        targetLanguage: _targetLang,
      );

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

          // Фонарик + настройки (справа вверху, как на экране Паспорт).
          Positioned(
            top: 50,
            right: 12,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _flashOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 26,
                  ),
                  onPressed: _isProcessing ? null : _toggleFlash,
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                  onPressed: () => widget.onSettings(),
                ),
              ],
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

          // Нижний бар: затемнение-градиент (как на остальных экранах
          // камеры через CameraControlsBar), внутри — галерея слева,
          // кнопка перевода по центру, выбор языка справа.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: SizedBox(
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Галерея — слева
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: _isProcessing ? null : _pickImageAndTranslate,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: _isProcessing ? Colors.grey : Colors.white,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.photo_library,
                            color: _isProcessing ? Colors.grey : Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),

                    // Кнопка перевода — по центру
                    FloatingActionButton(
                      heroTag: 'translateFab',
                      onPressed: _isProcessing ? null : _translateImage,
                      backgroundColor:
                          _isProcessing ? Colors.grey : const Color(0xFF2CA5E0),
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Icon(Icons.translate, size: 30),
                    ),

                    // Выбор целевого языка — справа
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _isProcessing ? null : _showLanguagePicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.language,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _languages[_targetLang] ?? _targetLang,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down,
                                  color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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