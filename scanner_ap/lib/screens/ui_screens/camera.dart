//Главный экран камеры — центральная точка всех режимов съёмки.
//
//Управляет переключением между режимами через горизонтальный список вверху экрана.
//Каждый режим использует свой специализированный виджет-камеру.
//
//Режимы (определены в camera_features.dart):
//- **Паспорт** → PassportCameraView (1 или 2 страницы)
//- **ID-карта** → IdCardCameraView (лицевая + обратная)
//- **Документ** → MultiPageDocumentView (до 10 страниц)
//- **+100 страниц** → UnlimitedDocumentView (premium, без лимита)
//- **QR-код** → встроенный сканер QrView
//- **Перевод** → TranslateCamera
//- **Подпись** → SignatureScreen
//- **OCR** → OcrScreen
//- **Импорт документов** → DocumentImporter (заглушка)
//
//Принимает параметры:
//- [initialFeature] — название режима для автоматического выбора при открытии
//- [importedDocumentPath] — путь к файлу при открытии через импорт
//- [onScanCompleted] — колбэк после завершения сканирования
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'camera_features.dart';
import 'capture_modes.dart';
import 'passport/photo_preview_passport.dart';
import 'id_card/id_card_photo_preview.dart';
import 'passport/passport_camera.dart';
import 'id_card/id_card_camera.dart';
import 'documents/documents_camera.dart';
import 'documents/documents_photo_preview.dart';
import 'translate/translate_camera.dart';
import '+10 ten page/plus_ten_page_camera.dart';
import 'importDocument/document_importer.dart';
import 'ocr/ocr_screen.dart';
import 'ocr/ocr_camera_view.dart';
import 'signature/home_screen.dart' as sig;
import 'color_adjustment_screen.dart';
import 'remove_spots_screen.dart';
import 'highlight_screen.dart';
import 'add_password_screen.dart';
import 'remove_watermark_screen.dart';
import 'document_ai_screen.dart';
import 'settings_screen.dart';


class CameraScreen extends StatefulWidget {
  final Function(String)? onScanCompleted;
  final String? initialFeature;
  final String? importedDocumentPath;

  const CameraScreen({
    super.key,
    this.onScanCompleted,
    this.initialFeature,
    this.importedDocumentPath,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

 
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isInitializingCamera = false;
  int _cameraSessionId = 0;


  // QR/штрихкоды распознаются через ML Kit на ОБЩЕЙ камере (_cameraController),
  // а не отдельным плагином — поэтому при входе в режим QR камера больше не
  // пересоздаётся (нет «выключилась/включилась»).
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  String? _qrCode;
  // История отсканированных кодов (персистентная, новые сверху).
  final List<String> _qrHistory = [];
  static const _qrHistoryKey = 'qr_scan_history';
  static const _qrHistoryMax = 30;
  bool _qrFlashOn = false;
  bool _isQrStreaming = false;   // активен ли image-stream сканирования
  bool _isBarcodeBusy = false;   // обрабатывается ли текущий кадр
  bool _qrCooldown = false;      // пауза после успешного скана (3 с)
  CameraDescription? _cameraDescription;

  // Соответствие ориентации устройства углу компенсации (Android).
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  

  final List<Map<String, dynamic>> _features = [...cameraFeatures];
  late String _selectedFeature;
  String _pageMode = '1 страница';

  final CaptureModeController captureModeController = CaptureModeController();
  late AnimationController _detectionAnimationController;

  bool _isDocumentDetected = false;
  bool _isScanning = false;

  XFile? _firstCapturedImage;
  XFile? _secondCapturedImage;
  XFile? _idCardFrontImage;
  XFile? _idCardBackImage;
  String _currentSide = 'Лицевая';
  List<XFile> _multiPageBatch = [];
  int get _currentBatchPageCount => _multiPageBatch.length;

  late ScrollController _featureScrollController;
  bool _isInitialScrollDone = false;


  String? _importedDocumentPath;

  @override
  void initState() {
    super.initState();

    _featureScrollController = ScrollController();
    WidgetsBinding.instance.addObserver(this);

    _detectionAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _importedDocumentPath = widget.importedDocumentPath;

    if (_importedDocumentPath != null) {
      Future.microtask(() {
        widget.onScanCompleted?.call(_importedDocumentPath!);
      });
    }

    if (widget.initialFeature != null) {
      final featureExists = _features.any((f) => f['name'] == widget.initialFeature);
      _selectedFeature = featureExists
          ? widget.initialFeature!
          : _features.first['name']!;
    } else {
      _selectedFeature = _features.first['name']!;
    }

    if (_importedDocumentPath == null) {
      // QR теперь тоже работает на общей камере, поэтому инициализируем её
      // во всех режимах и при QR сразу запускаем сканирование штрихкодов.
      _initializeCamera().then((_) {
        if (mounted && _selectedFeature == 'Сканер qr-код') {
          _startBarcodeScanning();
        }
      });
      // Для «Перевод», «OCR» и «QR» детекция документа не нужна: захват
      // ручной, а активный image-stream помешал бы takePicture().
      if (_selectedFeature != 'Перевод' &&
          _selectedFeature != 'OCR' &&
          _selectedFeature != 'Сканер qr-код') {
        Future.delayed(const Duration(milliseconds: 300), _startDocumentDetectionStream);
      }
    }

    _loadQrHistory();
  }

  @override
  void dispose() {
    _featureScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);

    unawaited(_disposeCameraController());

    unawaited(_barcodeScanner.close());

    captureModeController.detectionTimer?.cancel();
    captureModeController.detectionTimer = null;
    _detectionAnimationController.dispose();
    super.dispose();
  }

  void setImportedDocument(String path) {
    setState(() => _importedDocumentPath = path);
    widget.onScanCompleted?.call(path);
  }

  Future<void> _disposeCameraController() async {
    final controller = _cameraController;
    _cameraController = null;
    _cameraSessionId++;
    _isInitializingCamera = false;
    // Стрим QR останавливается вместе с контроллером — сбрасываем флаг.
    _isQrStreaming = false;

    if (mounted) {
      setState(() => _isCameraInitialized = false);
    } else {
      _isCameraInitialized = false;
    }

    if (controller != null) {
      try {
        await controller.dispose();
      } catch (_) {
        // Ignore dispose errors during fast lifecycle transitions.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // QR теперь работает на общей камере, поэтому путь один для всех режимов.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        unawaited(_disposeCameraController());
      }
    } else if (state == AppLifecycleState.resumed) {
      // Камера могла быть выгружена, когда системная галерея/share/etc.
      // перевели приложение в фон. На resumed всегда восстанавливаем —
      // и, если активен режим QR, заново запускаем сканирование.
      if (_cameraController == null && !_isInitializingCamera) {
        unawaited(_initializeCamera().then((_) {
          if (mounted && _selectedFeature == 'Сканер qr-код') {
            _startBarcodeScanning();
          }
        }));
      }
    }
  }

  /// Гарантирует, что камера готова к использованию. Вызывается после
  /// возврата из инструментальных экранов — там image_picker открывал
  /// системную галерею и мог уронить контроллер.
  Future<void> _ensureCameraReady() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (_selectedFeature == 'Сканер qr-код' && !_isQrStreaming) {
        _startBarcodeScanning();
      }
      return;
    }
    if (_isInitializingCamera) return;
    await _initializeCamera();
    if (mounted && _selectedFeature == 'Сканер qr-код') {
      _startBarcodeScanning();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
    final sessionId = ++_cameraSessionId;

    try {
      final previousController = _cameraController;
      _cameraController = null;
      if (previousController != null) {
        try {
          await previousController.dispose();
        } catch (_) {}
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final backCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = backCamera;

      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // yuv420 (Android) — с ним РАБОТАЕТ превью. Прямой nv21 на многих
        // устройствах гасит preview-surface (формат идёт только в
        // ImageReader) → чёрный экран. Для ML Kit конвертируем кадр
        // yuv420→nv21 в Dart (см. _inputImageFromCameraImage).
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted || sessionId != _cameraSessionId) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      setState(() => _isCameraInitialized = true);
    } catch (e) {
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      } else {
        _isCameraInitialized = false;
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  void _setCaptureModeAuto() {
    captureModeController.setCaptureMode("Автоматически");
    if (_selectedFeature != 'Перевод' && _selectedFeature != 'Сканер qr-код') {
      _startDocumentDetectionStream();
    }
  }

  void _setCaptureModeManual() {
    setState(() {
      captureModeController.setCaptureMode("Вручную");
      _isDocumentDetected = false;
      captureModeController.resetDetectionState();
    });
  }

  void _startDocumentDetectionStream() {
    if (_selectedFeature == 'Сканер qr-код') return;

    final feature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    final bool isDocumentMode = feature['isDocument'] == true;

    if (captureModeController.captureMode == 'Вручную') {
      captureModeController.resetDetectionState();
      setState(() => _isDocumentDetected = false);
      return;
    }

    captureModeController.startDetectionStream(
      isDocumentMode: isDocumentMode,
      onDetectionChanged: (detected) {
        if (mounted) setState(() => _isDocumentDetected = detected);
      },
      animationController: _detectionAnimationController,
    );
  }

  void _resetTwoPageState() {
    _firstCapturedImage = null;
    _secondCapturedImage = null;
  }

  void _resetIdCardState() {
    _idCardFrontImage = null;
    _idCardBackImage = null;
    _currentSide = 'Лицевая';
  }

  void _resetMultiPageState() {
    _multiPageBatch = [];
  }

  Future<void> _onFinishBatch() async {
    if (_multiPageBatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).camBatchEmpty)),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiPageDocumentPreviewScreen(
          imageFiles: _multiPageBatch,
          onRetakeAll: () {
            Navigator.popUntil(context, (route) => route.isFirst);
            _resetMultiPageState();
            if (_selectedFeature != 'Перевод') {
              _startDocumentDetectionStream();
            }
          },
          onSaveBatch: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            widget.onScanCompleted?.call(editedPaths.first);
            _resetMultiPageState();
            if (_selectedFeature != 'Перевод') {
              _startDocumentDetectionStream();
            }
          },
        ),
      ),
    );

    if (_selectedFeature != 'Перевод') {
      _startDocumentDetectionStream();
    }
  }

  void _onClearBatch() {
    _resetMultiPageState();
    if (_selectedFeature != 'Перевод') {
      _startDocumentDetectionStream();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).camBatchCleared)),
    );
  }

  
  Future<void> _takePicture() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isScanning ||
        _selectedFeature == 'Сканер qr-код') {
      return;
    }

    if (_selectedFeature == 'Перевод') {
      return;
    }

    final currentFeature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    final bool isDocumentMode = currentFeature['isDocument'] == true;
    final bool isMultiPageLimited = _selectedFeature == "Документ";
    final bool isMultiPageUnlimited = _selectedFeature == "+10 страниц";

    final l10n = AppLocalizations.of(context);
    if (!captureModeController.canTakePicture(isDocumentMode: isDocumentMode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.camWaitingDocument),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    captureModeController.resetDetectionState();
    // Устанавливаем флаг синхронно до первого await, чтобы исключить race condition
    _isScanning = true;
    captureModeController.isScanning = true;
    setState(() => _isDocumentDetected = false);

    try {
      XFile file = await _cameraController!.takePicture();
      if (!mounted) return;

      if (isMultiPageLimited || isMultiPageUnlimited) {
        if (isMultiPageLimited) {
          const int maxPages = 10;
          if (_currentBatchPageCount >= maxPages) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.camMaxPages)),
            );
            _isScanning = false;
            captureModeController.isScanning = false;
            _startDocumentDetectionStream();
            return;
          }
        }

        _multiPageBatch.add(file);
        setState(() {});

        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.camPageAdded(_multiPageBatch.length)),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      if (_selectedFeature == "Удостоверение личности") {
        if (_currentSide == "Лицевая") {
          setState(() {
            _idCardFrontImage = file;
            _currentSide = 'Обратная';
          });
          _isScanning = false;
          captureModeController.isScanning = false;
          _startDocumentDetectionStream();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.camFrontReady),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        _idCardBackImage = file;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IdCardPhotoPreviewScreen(
              frontImage: _idCardFrontImage!,
              backImage: _idCardBackImage!,
              onRetake: () {
                Navigator.popUntil(context, (route) => route.isFirst);
                _resetIdCardState();
                _startDocumentDetectionStream();
              },
              onConfirm: () {
                widget.onScanCompleted?.call(_idCardFrontImage!.path);
              },
            ),
          ),
        );

        _resetIdCardState();
        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();
        return;
      }

      if (currentFeature['hasTwoPageMode'] == true && _pageMode == "2 страницы") {
        if (_firstCapturedImage == null) {
          setState(() => _firstCapturedImage = file);
          _isScanning = false;
          captureModeController.isScanning = false;
          _startDocumentDetectionStream();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.camFirstPageReady),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        _secondCapturedImage = file;
        await _openPreview(
          imageFile: _firstCapturedImage!,
          secondImageFile: _secondCapturedImage!,
          isTwoPage: true,
        );

        _resetTwoPageState();
        return;
      }

      await _openPreview(
        imageFile: file,
        isTwoPage: false,
      );

      setState(() {
        _isScanning = false;
        captureModeController.isScanning = false;
      });
      _startDocumentDetectionStream();

    } catch (e) {
      setState(() {
        _isScanning = false;
        captureModeController.isScanning = false;
      });
      _startDocumentDetectionStream();
    }
  }

  Future<XFile?> _takePictureForTranslation() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    try {
      return await _cameraController!.takePicture();
    } catch (e) {
      return null;
    }
  }

  /// Открывает OCR-экран с уже снятым/выбранным изображением и
  /// автозапуском распознавания.
  Future<void> _runOcrWith(XFile file) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OcrScreen(initialImage: File(file.path)),
      ),
    );
    if (mounted) unawaited(_ensureCameraReady());
  }

  /// Съёмка в режиме OCR. Детекция документа для OCR не запускается
  /// (см. условия в initState и селекторе), поэтому image-stream не
  /// активен и takePicture() не конфликтует с ним.
  Future<void> _captureForOcr() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final XFile file = await _cameraController!.takePicture();
      await _runOcrWith(file);
    } catch (e) {
      debugPrint('Ошибка съёмки (OCR): $e');
    }
  }

  Future<void> _pickImageForOcr() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    await _runOcrWith(image);
  }

  Future<void> _openPreview({
    required XFile imageFile,
    XFile? secondImageFile,
    required bool isTwoPage,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoPreviewScreen(
          imageFile: imageFile,
          secondImageFile: secondImageFile,
          isTwoPageMode: isTwoPage,
          onRetake: () {
            Navigator.pop(context);
            _startDocumentDetectionStream();
          },
          onConfirm: () {
            widget.onScanCompleted?.call(imageFile.path);
          },
        ),
      ),
    );
    _startDocumentDetectionStream();
  }

  Future<void> _pickImageFromGallery() async {
    final l10n = AppLocalizations.of(context);
    final ImagePicker picker = ImagePicker();
    final XFile? galleryImage = await picker.pickImage(source: ImageSource.gallery);

    if (galleryImage == null) return;
    if (!mounted) return;

    if (_selectedFeature == 'Сканер qr-код') return;

    final bool isMultiPageLimited = _selectedFeature == "Документ";
    final bool isMultiPageUnlimited = _selectedFeature == "+10 страниц";

    if (isMultiPageLimited || isMultiPageUnlimited) {
      if (isMultiPageLimited) {
        const int maxPages = 10;
        if (_currentBatchPageCount >= maxPages) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.camMaxPages)),
          );
          return;
        }
      }

      _multiPageBatch.add(galleryImage);
      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.camPageFromGallery(_multiPageBatch.length)),
          duration: const Duration(seconds: 2),
        ),
      );
      _startDocumentDetectionStream();
      return;
    }

    await _openPreview(imageFile: galleryImage, isTwoPage: false);
  }

  void _setPageMode(String mode) {
    setState(() => _pageMode = mode);
  }

  void _scrollToSelectedFeature() {
    if (!mounted) return;

    final index = _features.indexWhere((f) => f['name'] == _selectedFeature);
    if (index == -1) return;

    if (!_featureScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _featureScrollController.hasClients) {
          _scrollToSelectedFeature();
        }
      });
      return;
    }

    // Значения ДОЛЖНЫ совпадать с _buildFeatureSelector: ширина тайла
    // зависит от компактности экрана, а у ListView есть ведущий padding 12.
    // Раньше здесь были захардкожены 120/360 — из-за завышенной itemWidth
    // расчёт давал перелёт, и выбранный режим (например «Перевод») уезжал
    // за левый край («вод» вместо «Перевод»).
    final isCompact = MediaQuery.of(context).size.width < 360;
    final double itemWidth = isCompact ? 72.0 : 84.0;
    const double leadingPadding = 12.0;
    final double viewportWidth =
        _featureScrollController.position.viewportDimension;

    // Центр выбранного тайла в координатах контента, центрируем в вьюпорте.
    final double itemCenter = leadingPadding + index * itemWidth + itemWidth / 2;
    final double targetOffset = itemCenter - (viewportWidth / 2);

    final maxOffset = _featureScrollController.position.maxScrollExtent;
    final minOffset = _featureScrollController.position.minScrollExtent;
    final constrainedOffset = targetOffset.clamp(minOffset, maxOffset);

    _featureScrollController.animateTo(
      constrainedOffset,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );

    _isInitialScrollDone = true;
  }


  Future<void> _launchInBrowser(String string) async {
    String urlString = string;


    if (!urlString.toLowerCase().startsWith('http://') &&
        !urlString.toLowerCase().startsWith('https://') &&
        !urlString.toLowerCase().startsWith('mailto:') &&
        !urlString.toLowerCase().startsWith('tel:')) {
      urlString = 'https://$string';
    }

    Uri? uri = Uri.tryParse(urlString);

    try {
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception("Invalid URI format: $string");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).camCantOpenLink(string, e.runtimeType.toString())),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Открывает экран настроек приложения. Привязан к иконке-шестерёнке
  /// во всех режимах камеры (раньше колбэк был пустым — иконка ничего не
  /// делала).
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  /// Фонарик в режиме QR теперь использует общий CameraController.
  Future<void> _toggleQrFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final on = controller.value.flashMode == FlashMode.torch;
      await controller.setFlashMode(on ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _qrFlashOn = !on);
    } catch (e) {
      debugPrint('Ошибка переключения фонарика QR: $e');
    }
  }

  /// Запускает image-stream и распознавание штрихкодов на общей камере.
  Future<void> _startBarcodeScanning() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isQrStreaming) return;
    try {
      // Если активен чужой стрим (живой перевод не успел остановиться при
      // переключении) — гасим его перед стартом сканера.
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _isQrStreaming = true;
      await controller.startImageStream(_processBarcodeImage);
    } catch (e) {
      _isQrStreaming = false;
      debugPrint('Ошибка запуска стрима QR: $e');
    }
  }

  /// Останавливает распознавание штрихкодов (перед сменой режима/выгрузкой).
  Future<void> _stopBarcodeScanning() async {
    final controller = _cameraController;
    if (!_isQrStreaming) return;
    _isQrStreaming = false;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Ошибка остановки стрима QR: $e');
    }
  }

  Future<void> _loadQrHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_qrHistoryKey) ?? [];
    if (!mounted) return;
    setState(() {
      _qrHistory
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _addToHistory(String code) async {
    // Не дублируем тот же код, если он уже наверху.
    if (_qrHistory.isNotEmpty && _qrHistory.first == code) return;
    setState(() {
      _qrHistory.remove(code); // если был раньше — поднимаем наверх
      _qrHistory.insert(0, code);
      if (_qrHistory.length > _qrHistoryMax) {
        _qrHistory.removeRange(_qrHistoryMax, _qrHistory.length);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_qrHistoryKey, _qrHistory);
  }

  Future<void> _clearQrHistory() async {
    setState(() => _qrHistory.clear());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_qrHistoryKey);
  }

  Future<void> _processBarcodeImage(CameraImage image) async {
    if (_isBarcodeBusy || _qrCooldown || !mounted) return;
    _isBarcodeBusy = true;
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!mounted || _qrCooldown) return;

      final code = barcodes
          .map((b) => b.rawValue)
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (code == null) return;

      // Пауза после успешного скана — чтобы не открывать ссылку повторно
      // каждый кадр. Через 3 с снова разрешаем сканирование.
      _qrCooldown = true;
      setState(() => _qrCode = code);
      unawaited(_addToHistory(code));
      unawaited(_launchInBrowser(code));
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        _qrCooldown = false;
        if (_selectedFeature == 'Сканер qr-код') {
          setState(() => _qrCode = null);
        }
      });
    } catch (e) {
      debugPrint('Ошибка распознавания QR: $e');
    } finally {
      _isBarcodeBusy = false;
    }
  }

  /// Конвертирует кадр камеры в InputImage для ML Kit с учётом поворота.
  /// На Android камера отдаёт yuv420 (3 плоскости) ради рабочего превью —
  /// здесь складываем его в однопланарный NV21, который нужен ML Kit.
  /// На iOS — bgra8888 как есть.
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _cameraController;
    final camera = _cameraDescription;
    if (controller == null || camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
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

    // Android: yuv420 → nv21.
    if (image.planes.length != 3) return null;
    final nv21 = _yuv420ToNv21(image);
    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.width, // NV21: строка яркости = ширина
      ),
    );
  }

  /// Складывает планарный YUV_420_888 в NV21 (Y + чередование V/U) с учётом
  /// rowStride/pixelStride плоскостей.
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
        out[pos++] = vPlane.bytes[i]; // V
        out[pos++] = uPlane.bytes[i]; // U
      }
    }
    return out;
  }

  void _afterToolReturn(_) {
    widget.onScanCompleted?.call('');
    unawaited(_ensureCameraReady());
  }

  bool _openToolFeature(Map<String, dynamic> feature) {
    final IconData? icon = feature['icon'] as IconData?;

    if (icon == Icons.edit) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const sig.HomeScreen()),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.restore) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ColorAdjustmentScreen(
            onImageSaved: () => widget.onScanCompleted?.call(''),
          ),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.cleaning_services) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RemoveSpotsScreen(
            onImageSaved: () => widget.onScanCompleted?.call(''),
          ),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.highlight) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HighlightScreen(onSaved: () => widget.onScanCompleted?.call('')),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.vpn_key_outlined) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddPasswordScreen(onSaved: () => widget.onScanCompleted?.call('')),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.delete_forever_outlined) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RemoveWatermarkScreen(onSaved: () => widget.onScanCompleted?.call('')),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.eco) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DocumentAiScreen.eco()),
      ).then(_afterToolReturn);
      return true;
    }

    return false;
  }

  Widget _buildQrCodeView() {
    final l10n = AppLocalizations.of(context);
    // Превью камеры рисует общий persistentCameraPreview под этим оверлеем
    // (камера теперь не пересоздаётся при входе в QR — нет мерцания).
    return Stack(
      children: [
        // Рамка-видоискатель в верхней половине (как на экране Паспорт),
        // чтобы не перекрывалась нижней плашкой и селектором режимов.
        Align(
          alignment: const Alignment(0, -0.25),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.66,
            height: MediaQuery.of(context).size.width * 0.66,
            decoration: BoxDecoration(
              border: Border.all(
                color: _qrCode != null ? Colors.greenAccent : Colors.white,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Подсказка прямо под рамкой.
        Align(
          alignment: const Alignment(0, 0.30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.qrScanHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),

        // Верхняя панель: назад, фонарик, настройки.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 28),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _toggleQrFlash,
                        child: Icon(
                          _qrFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _openSettings,
                        child: const Icon(Icons.settings,
                            color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Нижняя плашка — история отсканированных кодов (горизонтальная
        // лента, новые слева). Тап по чипу — снова открыть ссылку. Появляется
        // только когда история непуста.
        if (_qrHistory.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8, 8, 8, 8 + MediaQuery.of(context).padding.bottom,
              ),
              color: Colors.black.withValues(alpha: 0.5),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white70, size: 22),
                      tooltip: l10n.actionDelete,
                      onPressed: _clearQrHistory,
                    ),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _qrHistory.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => _buildQrHistoryChip(_qrHistory[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQrHistoryChip(String code) {
    return GestureDetector(
      onTap: () => _launchInBrowser(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeatureSelector() {
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 360;
    final tileWidth = isCompact ? 72.0 : 84.0;
    final fontSize = isCompact ? 10.5 : 11.5;
    final iconSize = isCompact ? 20.0 : 24.0;
    final horizontalPad = isCompact ? 8.0 : 10.0;

    return SizedBox(
      height: isCompact ? 82 : 90,
      child: ListView.builder(
        controller: _featureScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _features.length,
        itemBuilder: (context, index) {
          final feature = _features[index];
          final newFeature = feature['name']!;
          final isSelected = _selectedFeature == newFeature;

          return GestureDetector(
            onTap: () {

              if (newFeature == 'Импорт документов') {
                final cameraContext = context;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (importerContext) => DocumentImporter(
                      initialPath: _importedDocumentPath,
                  
                      onConfirm: (selectedPath) {
                        Navigator.pop(importerContext);
                        widget.onScanCompleted?.call(selectedPath);
                        Navigator.pop(cameraContext, selectedPath);
                      },
                      onBack: () {
                        Navigator.pop(importerContext);
                      },
                    ),
                  ),
                );
                return;
              }

              if (_openToolFeature(feature)) {
                return;
              }

              setState(() {
                _selectedFeature = newFeature;
                _pageMode = '1 страница';
                _resetTwoPageState();
                _resetIdCardState();
                _resetMultiPageState();

                if (_selectedFeature != 'Сканер qr-код') {
                  _qrCode = null;
                }
              });

              if (newFeature == 'Сканер qr-код') {
                // Камеру НЕ пересоздаём — запускаем сканирование штрихкодов
                // на уже работающем контроллере (нет мерцания). Детекцию
                // документа выключаем.
                captureModeController.detectionTimer?.cancel();
                captureModeController.resetDetectionState();
                setState(() => _isDocumentDetected = false);

                if (_cameraController == null) {
                  unawaited(_initializeCamera().then((_) {
                    if (mounted && _selectedFeature == 'Сканер qr-код') {
                      _startBarcodeScanning();
                    }
                  }));
                } else {
                  // Отложенно: даём предыдущему вью (напр. живой перевод)
                  // в dispose остановить свой стрим раньше старта сканера.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedFeature == 'Сканер qr-код') {
                      _startBarcodeScanning();
                    }
                  });
                }
              } else {
                // Уходим из QR — останавливаем стрим, иначе takePicture()
                // в документных режимах конфликтует с активным image-stream.
                unawaited(_stopBarcodeScanning());

                if (_cameraController == null) {
                  unawaited(_initializeCamera());
                }

                if (newFeature != 'Перевод' && newFeature != 'OCR') {
                  Future.delayed(const Duration(milliseconds: 500), _startDocumentDetectionStream);
                } else {
                  captureModeController.resetDetectionState();
                  setState(() => _isDocumentDetected = false);
                }
              }
              

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _scrollToSelectedFeature();
                }
              });
            },
            child: SizedBox(
              width: tileWidth,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPad * 0.4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: isCompact ? 40 : 48,
                      height: isCompact ? 40 : 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? const Color(0xFF2CA5E0)
                            : Colors.white.withValues(alpha: 0.14),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF2CA5E0)
                                      .withValues(alpha: 0.55),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        feature['icon'] ?? Icons.circle,
                        size: iconSize,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        (feature['label'] ?? feature['name']) as String,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.15,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.7),
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Превью камеры с сохранением aspect-ratio сенсора.
  /// `previewSize` у пакета camera возвращается в landscape (width > height)
  /// даже на портретной ориентации — поэтому в SizedBox swap-аем стороны.
  /// FittedBox(cover) заполняет весь Stack, обрезая лишние края, но не
  /// растягивает изображение по одной из осей.
  Widget _buildAspectCorrectPreview(CameraController controller) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_importedDocumentPath != null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            "Документ импортирован...",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isInitialScrollDone && mounted && _isCameraInitialized) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _scrollToSelectedFeature();
          }
        });
      }
    });

  
    if (!_isCameraInitialized && _selectedFeature != 'Перевод') {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Инициализация камеры...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final Map<String, Widget Function()> featureViews = {
      'Паспорт': () => PassportCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        pageMode: _pageMode,
        takePicture: _takePicture,
        setPageMode: _setPageMode,
        resetTwoPageState: _resetTwoPageState,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAuto,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      'Удостоверение личности': () => IdCardCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        currentSide: _currentSide,
        takePicture: _takePicture,
        resetIdCardState: _resetIdCardState,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAuto,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      'Документ': () => MultiPageDocumentView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAuto,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        currentBatchPageCount: _currentBatchPageCount,
        onFinishBatch: _onFinishBatch,
        onClearBatch: _onClearBatch,
      ),
      '+10 страниц': () => UnlimitedDocumentView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAuto,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        currentBatchPageCount: _currentBatchPageCount,
        onFinishBatch: _onFinishBatch,
        onClearBatch: _onClearBatch,
      ),
      'Перевод': () => TranslateCamera(
        cameraController: _cameraController,
        takePicture: _takePictureForTranslation,
        pickImageFromGallery: _pickImageFromGallery,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        onScanCompleted: widget.onScanCompleted,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        setCaptureModeAuto: _setCaptureModeAuto,
        setCaptureModeManual: _setCaptureModeManual,
      ),
      'OCR': () => OcrCameraView(
        cameraController: _cameraController,
        onCapture: _captureForOcr,
        onPickGallery: _pickImageForOcr,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      'Сканер qr-код': () => _buildQrCodeView(),
    };

    Widget currentCameraView = featureViews[_selectedFeature]?.call() ??
        Container(
          color: Colors.black,
          child: Center(
            child: Text(
              'Режим "$_selectedFeature" не реализован',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        );

    // QR теперь использует общий persistentCameraPreview (раньше был
    // исключён — отдельный плагин рисовал своё превью).
    final bool showPersistentPreview = _isCameraInitialized
        && _cameraController != null;
    final bool isTranslateSelected = _selectedFeature == 'Перевод';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Стабильный, всегда смонтированный слой превью — не пересоздаётся
          // при переключении режимов, чтобы камера не мерцала.
          // FittedBox(cover) сохраняет aspect-ratio сенсора — preview больше
          // не растягивается, на экране показывается «обрезанный» центр
          // (как нативная камера в Android), без искажения пропорций.
          Positioned.fill(
            key: const ValueKey('persistentCameraPreview'),
            child: showPersistentPreview
                ? _buildAspectCorrectPreview(_cameraController!)
                : const ColoredBox(color: Colors.black),
          ),
          Positioned.fill(child: currentCameraView),
          Positioned(
            // CameraControlsBar (child-view bottom-bar) уже включает
            // SafeArea и сам встаёт на bottom:0. Селектор сидит точно над
            // ним — высота bar'а ~78 + 32 padding + safeBottom; берём
            // 110 + safeBottom как стабильный отступ.
            bottom: MediaQuery.of(context).padding.bottom + 110,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: isTranslateSelected ? 0.22 : 0.12,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(
                      alpha: isTranslateSelected ? 0.1 : 0,
                    ),
                    Colors.black.withValues(
                      alpha: isTranslateSelected ? 0.55 : 0.35,
                    ),
                  ],
                ),
              ),
              child: _buildFeatureSelector(),
            ),
          ),
        ],
      ),
    );
  }
}
