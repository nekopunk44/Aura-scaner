import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import '../../../l10n/app_localizations.dart';

import 'apis/recognition_api.dart';
import 'apis/translation_api.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:image_picker/image_picker.dart';

/// Экран перевода с ЖИВЫМ переводом прямо в камере: наводишь на текст в
/// рамке — перевод появляется на экране в реальном времени (без кнопки).
///
/// Живой пайплайн: image-stream → ML Kit Text Recognition (latin) →
/// определение языка → OnDeviceTranslator → текст. Для оффлайн-перевода
/// при первом использовании языковой пары качаются модели (~30 МБ).
///
/// Галерея остаётся как разовый перевод (через Tesseract — поддерживает
/// кириллицу), результат показывается модально.
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
  // --- Разовый перевод из галереи (модальное окно) ---
  String? _shownText;
  bool _isProcessing = false;

  // --- Живой перевод ---
  String? _liveTranslation;
  String? _detectedSourceLang; // BCP-код исходного языка (для бейджа «EN → RU»)
  bool _streaming = false;
  bool _busy = false;
  bool _downloadingModels = false;
  bool _targetInitialized = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastRecognized = '';

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final LanguageIdentifier _langId =
      LanguageIdentifier(confidenceThreshold: 0.4);
  final OnDeviceTranslatorModelManager _modelManager =
      OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _translator;
  String? _translatorKey;

  String _targetLang = 'ru';
  bool _flashOn = false;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Поддерживаемые целевые языки (коды совпадают с ML Kit). Названия — на
  /// родном языке, переводить их не нужно.
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

  @override
  void initState() {
    super.initState();
    // Старт после первого кадра — чтобы предыдущий стрим (напр. QR) успел
    // остановиться при переключении режима.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLiveStream());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Целевой язык по умолчанию = язык приложения (а не всегда русский).
    if (!_targetInitialized) {
      _targetInitialized = true;
      final appLang = Localizations.localeOf(context).languageCode;
      if (_languages.containsKey(appLang)) {
        _targetLang = appLang;
      }
    }
  }

  @override
  void didUpdateWidget(TranslateCamera oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Контроллер пересоздаётся при сворачивании/возврате из галереи —
    // старый стрим мёртв, перезапускаем на новом.
    if (oldWidget.cameraController != widget.cameraController) {
      _streaming = false;
      _busy = false;
      _lastRecognized = '';
      WidgetsBinding.instance.addPostFrameCallback((_) => _startLiveStream());
    }
  }

  @override
  void dispose() {
    _stopLiveStream();
    _recognizer.close();
    _langId.close();
    _translator?.close();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Живой стрим
  // ------------------------------------------------------------------

  Future<void> _startLiveStream() async {
    final c = widget.cameraController;
    if (c == null || !c.value.isInitialized || _streaming) return;
    // Если контроллер ещё занят предыдущим стримом — подождём и попробуем.
    if (c.value.isStreamingImages) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted || _streaming || c.value.isStreamingImages) return;
    }
    try {
      _streaming = true;
      await c.startImageStream(_processFrame);
    } catch (e) {
      _streaming = false;
      debugPrint('Перевод: ошибка старта стрима: $e');
    }
  }

  Future<void> _stopLiveStream() async {
    final c = widget.cameraController;
    if (!_streaming) return;
    _streaming = false;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (e) {
      debugPrint('Перевод: ошибка остановки стрима: $e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_busy || !mounted || _isProcessing) return;
    final now = DateTime.now();
    if (now.difference(_lastRun).inMilliseconds < 600) return;
    _busy = true;
    _lastRun = now;
    try {
      final input = _inputImageFromCameraImage(image);
      if (input == null) return;

      final recognized = await _recognizer.processImage(input);
      final text = recognized.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.length < 2) {
        _lastRecognized = '';
        if (_liveTranslation != null && mounted) {
          setState(() {
            _liveTranslation = null;
            _detectedSourceLang = null;
          });
        }
        return;
      }
      // Тот же текст — не переводим повторно (меньше мерцания).
      if (text == _lastRecognized) return;
      _lastRecognized = text;

      String srcCode;
      try {
        srcCode = await _langId.identifyLanguage(text);
      } catch (_) {
        srcCode = 'und';
      }
      final source = _mapToTranslateLang(srcCode) ?? TranslateLanguage.english;
      final target =
          _mapToTranslateLang(_targetLang) ?? TranslateLanguage.russian;

      if (source == target) {
        if (mounted) {
          setState(() {
            _liveTranslation = text;
            _detectedSourceLang = source.bcpCode;
          });
        }
        return;
      }

      final translator = await _ensureTranslator(source, target);
      if (translator == null) return;
      final translated = await translator.translateText(text);
      if (mounted) {
        setState(() {
          _liveTranslation = translated;
          _detectedSourceLang = source.bcpCode;
        });
      }
    } catch (e) {
      debugPrint('Перевод: ошибка кадра: $e');
    } finally {
      _busy = false;
    }
  }

  Future<OnDeviceTranslator?> _ensureTranslator(
    TranslateLanguage source,
    TranslateLanguage target,
  ) async {
    final key = '${source.bcpCode}_${target.bcpCode}';
    if (_translator != null && _translatorKey == key) return _translator;

    await _translator?.close();
    _translator = null;
    _translatorKey = null;

    try {
      for (final lang in [source, target]) {
        if (!await _modelManager.isModelDownloaded(lang.bcpCode)) {
          if (mounted) setState(() => _downloadingModels = true);
          await _modelManager.downloadModel(lang.bcpCode);
        }
      }
    } catch (e) {
      debugPrint('Перевод: ошибка загрузки моделей: $e');
      if (mounted) setState(() => _downloadingModels = false);
      return null;
    }
    if (mounted) setState(() => _downloadingModels = false);

    _translator = OnDeviceTranslator(
      sourceLanguage: source,
      targetLanguage: target,
    );
    _translatorKey = key;
    return _translator;
  }

  TranslateLanguage? _mapToTranslateLang(String code) {
    switch (code.toLowerCase().split('-')[0]) {
      case 'ru':
      case 'be':
      case 'uk':
        return TranslateLanguage.russian;
      case 'en':
        return TranslateLanguage.english;
      case 'es':
        return TranslateLanguage.spanish;
      case 'fr':
        return TranslateLanguage.french;
      case 'de':
        return TranslateLanguage.german;
      case 'it':
        return TranslateLanguage.italian;
      case 'pt':
        return TranslateLanguage.portuguese;
      case 'pl':
        return TranslateLanguage.polish;
      case 'tr':
        return TranslateLanguage.turkish;
      case 'ar':
        return TranslateLanguage.arabic;
      case 'zh':
        return TranslateLanguage.chinese;
      case 'ja':
        return TranslateLanguage.japanese;
      case 'ko':
        return TranslateLanguage.korean;
      default:
        return null;
    }
  }

  // ------------------------------------------------------------------
  // Конвертация кадра камеры в InputImage (yuv420→nv21 на Android)
  // ------------------------------------------------------------------

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final c = widget.cameraController;
    if (c == null) return null;
    final desc = c.description;
    final sensorOrientation = desc.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      var comp = _orientations[c.value.deviceOrientation];
      if (comp == null) return null;
      if (desc.lensDirection == CameraLensDirection.front) {
        comp = (sensorOrientation + comp) % 360;
      } else {
        comp = (sensorOrientation - comp + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;

    if (Platform.isIOS) {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format != InputImageFormat.bgra8888 || image.planes.length != 1) {
        return null;
      }
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    if (image.planes.length != 3) return null;
    final nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width,
      ),
    );
  }

  Uint8List _yuv420ToNv21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Uint8List out = Uint8List(width * height + (width * height ~/ 2));

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yRowStride = yPlane.bytesPerRow;
    final int yPixelStride = yPlane.bytesPerPixel ?? 1;
    int pos = 0;
    for (int row = 0; row < height; row++) {
      final int yOffset = row * yRowStride;
      for (int col = 0; col < width; col++) {
        out[pos++] = yPlane.bytes[yOffset + col * yPixelStride];
      }
    }

    final int uvRowStride = uPlane.bytesPerRow;
    final int uvPixelStride = uPlane.bytesPerPixel ?? 2;
    for (int row = 0; row < height ~/ 2; row++) {
      final int uvOffset = row * uvRowStride;
      for (int col = 0; col < width ~/ 2; col++) {
        final int i = uvOffset + col * uvPixelStride;
        out[pos++] = vPlane.bytes[i];
        out[pos++] = uPlane.bytes[i];
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // UI-управление
  // ------------------------------------------------------------------

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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  AppLocalizations.of(sheetContext).translateTargetTitle,
                  style: const TextStyle(
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
                        setState(() {
                          _targetLang = e.key;
                          // Смена цели — пересоздать переводчик и заново
                          // перевести текущий текст.
                          _lastRecognized = '';
                          _liveTranslation = null;
                          _detectedSourceLang = null;
                        });
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

  /// Разовый перевод выбранного из галереи изображения (через Tesseract —
  /// поддерживает кириллицу). Результат — в модальном окне.
  Future<void> _pickImageAndTranslate() async {
    final l10n = AppLocalizations.of(context);
    try {
      setState(() {
        _isProcessing = true;
        _shownText = l10n.translateProcessing;
      });

      final ImagePicker picker = ImagePicker();
      final XFile? galleryImage =
          await picker.pickImage(source: ImageSource.gallery);

      if (!mounted) return;
      if (galleryImage == null) {
        setState(() {
          _isProcessing = false;
          _shownText = null;
        });
        return;
      }

      final recognizedText = await RecognitionApi.recognizeText(
        InputImage.fromFile(File(galleryImage.path)),
      );

      if (!mounted) return;
      if (recognizedText == null || recognizedText.isEmpty) {
        setState(() {
          _shownText = l10n.translateNoText;
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
        _shownText = translatedText ?? l10n.translateFailed;
        _isProcessing = false;
      });

      if (widget.onScanCompleted != null && translatedText != null) {
        widget.onScanCompleted!(translatedText);
      }
    } catch (e) {
      debugPrint('Ошибка при выборе из галереи: $e');
      if (!mounted) return;
      setState(() {
        _shownText = l10n.translatePickFailed;
        _isProcessing = false;
      });
    }
  }

  // ------------------------------------------------------------------
  // build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Рамка наведения + живой перевод под ней.
          Align(
            alignment: const Alignment(0, -0.12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size.width * 0.84,
                  height: size.height * 0.34,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _liveTranslation != null
                          ? const Color(0xFF2CA5E0)
                          : Colors.white,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLivePanel(),
              ],
            ),
          ),

          // Кнопка Назад
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () => widget.onBack(),
            ),
          ),

          // Фонарик + настройки
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
                  onPressed: _toggleFlash,
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white, size: 26),
                  onPressed: () => widget.onSettings(),
                ),
              ],
            ),
          ),

          // Заголовок + подсказка
          Positioned(
            top: 96,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Builder(builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Column(
                  children: [
                    Text(
                      l10n.translateCameraTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.translateCameraHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                );
              }),
            ),
          ),

          // Нижний бар: галерея (слева) + выбор языка (справа).
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24, 20, 24, 20 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: _isProcessing ? null : _pickImageAndTranslate,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: _isProcessing ? Colors.grey : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.photo_library,
                          color: _isProcessing ? Colors.grey : Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _showLanguagePicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4)),
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
                  ],
                ),
              ),
            ),
          ),

          // Модальное окно результата из галереи.
          if (_shownText != null) _buildGalleryResult(),
        ],
      ),
    );
  }

  Widget _buildLivePanel() {
    final l10n = AppLocalizations.of(context);

    if (_downloadingModels) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                l10n.translateDownloadingModels,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    // Текста в рамке пока нет — статус-подсказка, чтобы было понятно,
    // что режим работает и «ищет».
    if (_liveTranslation == null || _liveTranslation!.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6, color: Colors.white54,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.translateSearchingText,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final srcLabel = _detectedSourceLang == null
        ? l10n.translateSourceAuto
        : _detectedSourceLang!.toUpperCase();
    final targetLabel = _targetLang.toUpperCase();

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.84,
        maxHeight: 168,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2CA5E0).withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Бейдж направления перевода: «EN → RU»
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2CA5E0).withValues(alpha: 0.16),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  srcLabel,
                  style: const TextStyle(
                    color: Color(0xFF7CC7F0),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 13, color: Color(0xFF7CC7F0)),
                ),
                Text(
                  targetLabel,
                  style: const TextStyle(
                    color: Color(0xFF7CC7F0),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                _liveTranslation!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryResult() {
    final l10n = AppLocalizations.of(context);
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l10n.translateResultTitle}:',
                  style: const TextStyle(
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
                      child: Text(l10n.actionClose),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (_shownText != null) {
                          Clipboard.setData(ClipboardData(text: _shownText!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.commonTextCopied),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Text(l10n.actionCopy),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
