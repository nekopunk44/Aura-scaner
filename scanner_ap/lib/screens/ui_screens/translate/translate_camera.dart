import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:ui' as ui;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/camera_capture_button.dart';
import '../../../widgets/camera_controls_bar.dart';
import '../../../widgets/camera_mode_switch.dart';
import '../../../widgets/document_guide_frame.dart';

import 'apis/recognition_api.dart';
import 'apis/translation_api.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

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
  bool _manualTranslateMode = false;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastRecognized = '';

  /// «Липкий» исходный язык: последний УВЕРЕННО определённый BCP-код.
  /// Короткие надписи (одно слово на обложке) идентификатор часто не
  /// распознаёт — тогда используем язык, определённый на предыдущих,
  /// более длинных кадрах, вместо молчаливого фолбэка на английский.
  String? _stickySourceLang;

  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final LanguageIdentifier _langId = LanguageIdentifier(
    confidenceThreshold: 0.4,
  );
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

  bool get _isAutoMode => !_manualTranslateMode;

  bool get _isManualMode => _manualTranslateMode;

  bool get _shouldShowFrameStatus =>
      _downloadingModels ||
      _isProcessing ||
      (_isAutoMode && (_liveTranslation == null || _liveTranslation!.isEmpty));

  @override
  void initState() {
    super.initState();
    // Старт после первого кадра — чтобы предыдущий стрим (напр. QR) успел
    // остановиться при переключении режима.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncLiveStreamWithMode(),
    );
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
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _syncLiveStreamWithMode(),
      );
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

  void _syncLiveStreamWithMode() {
    if (_isAutoMode) {
      _startLiveStream();
    } else {
      _stopLiveStream();
    }
  }

  Future<void> _startLiveStream() async {
    final c = widget.cameraController;
    if (!_isAutoMode || c == null || !c.value.isInitialized || _streaming) {
      return;
    }
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
    if (!_isAutoMode || _busy || !mounted || _isProcessing) return;
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

      await _translateRecognizedText(text);
    } catch (e) {
      debugPrint('Перевод: ошибка кадра: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _translateRecognizedText(
    String recognizedText, {
    bool finishProcessing = false,
  }) async {
    final text = recognizedText.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length < 2) {
      if (finishProcessing && mounted) {
        setState(() => _isProcessing = false);
      }
      return;
    }

    final source = await _identifySourceLanguage(text);
    final target =
        _mapToTranslateLang(_targetLang) ?? TranslateLanguage.russian;

    if (source == null) {
      // Язык не определён (и липкого нет) — показываем распознанный текст
      // БЕЗ перевода. Раньше здесь молча подставлялся английский, и
      // «PAŞAPORT» превращался в бессмысленный перевод «Порт».
      if (mounted) {
        setState(() {
          _liveTranslation = text;
          _detectedSourceLang = null;
          if (finishProcessing) _isProcessing = false;
        });
      }
      return;
    }

    String translated = text;
    if (source != target) {
      final translator = await _ensureTranslator(source, target);
      if (translator == null) {
        if (finishProcessing && mounted) {
          setState(() => _isProcessing = false);
        }
        return;
      }
      translated = await translator.translateText(text);
    }

    if (mounted) {
      setState(() {
        _liveTranslation = translated;
        _detectedSourceLang = source.bcpCode;
        if (finishProcessing) _isProcessing = false;
      });
    }
  }

  /// Определяет исходный язык по списку кандидатов ML Kit: берём первого
  /// достаточно уверенного (>= 0.5) из поддерживаемых переводом. При
  /// неудаче — «липкий» язык с предыдущих уверенных кадров, а если и его
  /// нет — null (вызывающий покажет оригинал без перевода).
  Future<TranslateLanguage?> _identifySourceLanguage(String text) async {
    try {
      final candidates = await _langId.identifyPossibleLanguages(text);
      for (final candidate in candidates) {
        if (candidate.languageTag == 'und') continue;
        if (candidate.confidence < 0.5) continue;
        final lang = _mapToTranslateLang(candidate.languageTag);
        if (lang != null) {
          _stickySourceLang = candidate.languageTag;
          return lang;
        }
      }
    } catch (e) {
      debugPrint('Перевод: ошибка определения языка: $e');
    }
    final sticky = _stickySourceLang;
    if (sticky != null) return _mapToTranslateLang(sticky);
    return null;
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
          // isWifiRequired по умолчанию true: на мобильном интернете
          // загрузка не падала, а бесконечно ждала Wi-Fi — «вечная
          // загрузка моделей». Качаем по любой сети + страховочный таймаут.
          await _modelManager
              .downloadModel(lang.bcpCode, isWifiRequired: false)
              .timeout(const Duration(seconds: 90));
        }
      }
    } catch (e) {
      debugPrint('Перевод: ошибка загрузки моделей: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _downloadingModels = false;
          // Показываем внятную ошибку вместо молчаливого зависания.
          _liveTranslation = l10n.translateFailed;
          _detectedSourceLang = null;
        });
      }
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

  /// Автоопределённый BCP-код → язык ML Kit. Поддерживаются ВСЕ ~59 языков
  /// on-device перевода (румынский, украинский, нидерландский и т.д.) —
  /// раньше карта знала только 13, и, например, румынский текст молча
  /// переводился «как английский».
  TranslateLanguage? _mapToTranslateLang(String code) {
    final base = code.toLowerCase().split('-')[0];
    if (base.isEmpty || base == 'und') return null;
    // Языки без собственной модели → ближайший родственный.
    if (base == 'be') return TranslateLanguage.russian;
    for (final lang in TranslateLanguage.values) {
      if (lang.bcpCode == base) return lang;
    }
    return null;
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
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
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
      final XFile? galleryImage = await picker.pickImage(
        source: ImageSource.gallery,
      );

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

  Future<void> _captureFrameAndTranslate() async {
    final l10n = AppLocalizations.of(context);
    if (_isProcessing) return;

    try {
      await _stopLiveStream();
      if (!mounted) return;

      setState(() {
        _isProcessing = true;
        _shownText = null;
        _liveTranslation = null;
        _detectedSourceLang = null;
      });

      final shot = await widget.takePicture();
      if (shot == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      final cropped = await _cropImageToTranslateFrame(shot);
      final recognizedText = await RecognitionApi.recognizeText(
        InputImage.fromFile(File(cropped.path)),
      );

      if (!mounted) return;
      if (recognizedText == null || recognizedText.trim().isEmpty) {
        setState(() {
          _liveTranslation = l10n.translateNoText;
          _detectedSourceLang = null;
          _isProcessing = false;
        });
        return;
      }

      await _translateRecognizedText(recognizedText, finishProcessing: true);
    } catch (e) {
      debugPrint('Перевод: ошибка ручного снимка: $e');
      if (!mounted) return;
      setState(() {
        _liveTranslation = l10n.translateFailed;
        _detectedSourceLang = null;
        _isProcessing = false;
      });
    }
  }

  Future<XFile> _cropImageToTranslateFrame(XFile file) async {
    try {
      final bytes = await File(file.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return file;

      final source = img.bakeOrientation(decoded);
      const aspectRatio = 1.42;
      const widthFactor = 0.85;
      const verticalAlignment = -0.25;

      final cropWidth = (source.width * widthFactor)
          .round()
          .clamp(1, source.width)
          .toInt();
      final frameHeight = cropWidth / aspectRatio;
      final cropHeight = frameHeight.round().clamp(1, source.height).toInt();
      final centerY =
          source.height / 2 +
          verticalAlignment * (source.height / 2 - cropHeight / 2);
      final x = ((source.width - cropWidth) / 2)
          .round()
          .clamp(0, source.width - cropWidth)
          .toInt();
      final y = (centerY - cropHeight / 2)
          .round()
          .clamp(0, source.height - cropHeight)
          .toInt();

      final cropped = img.copyCrop(
        source,
        x: x,
        y: y,
        width: cropWidth,
        height: cropHeight,
      );
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/translate_frame_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await out.writeAsBytes(img.encodeJpg(cropped, quality: 94));
      return XFile(out.path);
    } catch (e) {
      debugPrint('Перевод: ошибка crop по рамке: $e');
      return file;
    }
  }

  // ------------------------------------------------------------------
  // build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Рамка наведения + живой статус под ней.
          Positioned.fill(child: _buildFrameAndLivePanel()),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopPanel(AppLocalizations.of(context)),
          ),

          Positioned(
            top: 108,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Builder(
                builder: (context) {
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
                        _isAutoMode
                            ? l10n.translateCameraHint
                            : l10n.translateManualHint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          _buildTranslationResultCard(),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),

          if (_shownText != null) _buildGalleryResult(),
        ],
      ),
    );
  }

  // Переключатель Авто/Ручн. — общий виджет всех режимов камеры.
  Widget _buildModeSwitch(AppLocalizations l10n) {
    return CameraModeSwitch(
      autoLabel: l10n.camAutoLabel,
      manualLabel: l10n.camManualLabel,
      isAuto: _isAutoMode,
      onAuto: _setTranslateAutoMode,
      onManual: _setTranslateManualMode,
    );
  }

  Widget _buildTopPanel(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => widget.onBack(),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 28,
              ),
            ),
            _buildModeSwitch(l10n),
            Row(
              children: [
                GestureDetector(
                  onTap: _toggleFlash,
                  child: Icon(
                    _flashOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => widget.onSettings(),
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

  void _setTranslateAutoMode() {
    if (_isAutoMode) return;
    widget.setCaptureModeAuto();
    setState(() {
      _manualTranslateMode = false;
      _lastRecognized = '';
      _liveTranslation = null;
      _detectedSourceLang = null;
      _isProcessing = false;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncLiveStreamWithMode(),
    );
  }

  void _setTranslateManualMode() {
    if (_isManualMode) return;
    widget.setCaptureModeManual();
    _stopLiveStream();
    setState(() {
      _manualTranslateMode = true;
      _lastRecognized = '';
      _liveTranslation = null;
      _detectedSourceLang = null;
      _isProcessing = false;
    });
  }

  Widget _buildFrameAndLivePanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const aspectRatio = 1.42;
        const widthFactor = 0.85;
        const verticalAlignment = -0.25;

        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final frameWidth = w * widthFactor;
        final frameHeight = frameWidth / aspectRatio;
        final centerY = h / 2 + verticalAlignment * (h / 2 - frameHeight / 2);
        final rect = Rect.fromCenter(
          center: Offset(w / 2, centerY),
          width: frameWidth,
          height: frameHeight,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: DocumentGuideFrame(
                // Затемнение рисует общий слой камеры (морф между режимами).
                drawScrim: false,
                aspectRatio: aspectRatio,
                widthFactor: widthFactor,
                verticalAlignment: verticalAlignment,
                detected: false,
              ),
            ),
            if (_shouldShowFrameStatus)
              Positioned(
                left: 24,
                right: 24,
                top: rect.bottom + 14,
                child: Center(child: _buildLivePanel()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.30),
                Colors.black.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1,
            ),
          ),
          child: SizedBox(
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: CameraActionIcon(
                    icon: Icons.photo_library_outlined,
                    onTap: _isProcessing ? null : _pickImageAndTranslate,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildLanguageButton(),
                ),
                if (_isManualMode)
                  CameraCaptureButton(
                    onTap: _isProcessing ? null : _captureFrameAndTranslate,
                    isBusy: _isProcessing,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton() {
    return GestureDetector(
      onTap: _showLanguagePicker,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.28),
            width: 1.1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                _languages[_targetLang] ?? _targetLang,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
          ],
        ),
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
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
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
    if (_isProcessing) {
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
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: Colors.white54,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.translateProcessing,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_isAutoMode &&
        (_liveTranslation == null || _liveTranslation!.isEmpty)) {
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
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: Colors.white54,
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
        border: Border.all(
          color: const Color(0xFF2CA5E0).withValues(alpha: 0.6),
        ),
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
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
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: Color(0xFF7CC7F0),
                  ),
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

  Widget _buildTranslationResultCard() {
    final text = _liveTranslation;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final srcLabel = _detectedSourceLang == null
        ? l10n.translateSourceAuto
        : _detectedSourceLang!.toUpperCase();
    final targetLabel = _targetLang.toUpperCase();

    return Positioned(
      left: 32,
      right: 32,
      bottom: MediaQuery.of(context).padding.bottom + 220,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 168),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF2CA5E0).withValues(alpha: 0.75),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.18),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11),
                ),
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
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: Color(0xFF7CC7F0),
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ),
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
