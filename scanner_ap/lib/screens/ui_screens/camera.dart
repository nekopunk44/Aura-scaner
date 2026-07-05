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
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_cropper/image_cropper.dart';
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
import 'documents/save_options_document.dart';
import 'translate/translate_camera.dart';
import '+10 ten page/plus_ten_page_camera.dart';
import 'importDocument/document_importer.dart';
import 'ocr/ocr_screen.dart';
import 'ocr/ocr_camera_view.dart';
import 'remove_spots_camera_view.dart';
import 'remove_watermark_camera_view.dart';
import 'restore_photo_camera_view.dart';
import 'restore_photo_screen.dart';
import 'signature/home_screen.dart' as sig;
import 'remove_spots_screen.dart';
import 'highlight_screen.dart';
import 'add_password_screen.dart';
import 'remove_watermark_screen.dart';
import 'eco/eco_packaging_screen.dart';
import 'premium_paywall.dart';
import 'settings_screen.dart';
import '../../services/premium_service.dart';
import '../../utils/app_notification.dart';
import '../../utils/document_scanner.dart';
import '../../utils/id_card_scanner.dart';
import '../../utils/live_quad_detector.dart';
import '../../utils/passport_scanner.dart';

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

class _DocumentFrameSpec {
  const _DocumentFrameSpec({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final double left;
  final double right;
  final double top;
  final double bottom;
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const MethodChannel _nativeBridgeChannel = MethodChannel(
    'com.aurascanner.app/native_bridge',
  );
  static const Set<String> _premiumFeatureNames = {
    Feat.plus10Pages,
    Feat.restorePhoto,
    Feat.removeSpots,
    Feat.highlight,
    Feat.removeWatermark,
    Feat.addPassword,
    Feat.eco,
  };

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
  bool _isQrStreaming = false; // активен ли image-stream сканирования
  bool _isBarcodeBusy = false; // обрабатывается ли текущий кадр
  bool _qrCooldown = false; // пауза после успешного скана (3 с)
  bool _isDocumentDetectionStreaming = false;
  bool _isDocumentFrameBusy = false;
  int _documentFrameCounter = 0;
  int _quadDiagCounter = 0; // троттлинг диагностики живого контура
  // Живой контур фото для режима «Восстановить»: 4 угла в нормализованных
  // координатах сенсора (0..1), упорядочены tl,tr,br,bl. null — контур не
  // найден. Обновляется из стрима без setState (через ValueNotifier), чтобы
  // перерисовывалась только рамка, а не весь экран камеры.
  final ValueNotifier<List<Offset>?> _photoQuad = ValueNotifier<List<Offset>?>(
    null,
  );
  Timer? _autoCaptureTimer;
  String? _autoCaptureFeature;
  String? _autoCaptureSide;
  String? _autoCapturePageMode;
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
  // Стабилизация детекции документа: считаем подряд кадры с найденным/потерянным
  // контуром, чтобы не реагировать на дрожь и не снимать раньше времени.
  int _quadFoundFrames = 0;
  int _quadLostFrames = 0;
  static const int _kQuadStable = 4; // подряд кадров с контуром → «найден»
  static const int _kQuadLost = 3; // подряд кадров без контура → «потерян»
  // После первого кадра в многошаговом документном потоке ждём, пока
  // документ уберут из кадра, прежде чем авто-снимать следующую сторону
  // или страницу. Это защищает от мгновенного повторного снимка.
  bool _awaitDocumentExit = false;

  XFile? _firstCapturedImage;
  XFile? _secondCapturedImage;
  XFile? _idCardFrontImage;
  XFile? _idCardBackImage;
  List<XFile> _passportBatch = [];
  String _currentSide = 'Лицевая';
  List<XFile> _multiPageBatch = [];
  int get _currentBatchPageCount => _multiPageBatch.length;
  int get _documentTargetPageCount => 10;

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
      final featureExists = _features.any(
        (f) => f['name'] == widget.initialFeature,
      );
      final requestedFeature = featureExists
          ? widget.initialFeature!
          : _features.first['name']!;
      _selectedFeature = _canUseFeature(requestedFeature)
          ? requestedFeature
          : Feat.document;
    } else {
      _selectedFeature = _features.first['name']!;
    }

    if (_importedDocumentPath == null) {
      // QR теперь тоже работает на общей камере, поэтому инициализируем её
      // во всех режимах и при QR сразу запускаем сканирование штрихкодов.
      _initializeCamera().then((_) {
        if (mounted && _selectedFeature == Feat.qrScanner) {
          _startBarcodeScanning();
        }
      });
      // Для «Перевод», «OCR» и «QR» детекция документа не нужна: захват
      // ручной, а активный image-stream помешал бы takePicture().
      if (_selectedFeature != Feat.translate &&
          _selectedFeature != Feat.ocr &&
          _selectedFeature != Feat.qrScanner) {
        Future.delayed(
          const Duration(milliseconds: 300),
          _startDocumentDetectionStream,
        );
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
    _cancelAutoCapture();
    _detectionAnimationController.dispose();
    _photoQuad.dispose();
    super.dispose();
  }

  void setImportedDocument(String path) {
    setState(() => _importedDocumentPath = path);
    widget.onScanCompleted?.call(path);
  }

  Future<void> _disposeCameraController() async {
    _cancelAutoCapture();
    final controller = _cameraController;
    _cameraController = null;
    _cameraSessionId++;
    _isInitializingCamera = false;
    // Стрим QR останавливается вместе с контроллером — сбрасываем флаг.
    _isQrStreaming = false;
    _isDocumentDetectionStreaming = false;
    _isDocumentFrameBusy = false;
    _documentFrameCounter = 0;

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
        unawaited(
          _initializeCamera().then((_) {
            if (!mounted) return;
            if (_selectedFeature == Feat.qrScanner) {
              unawaited(_startBarcodeScanning());
            } else if (_selectedFeature != Feat.translate &&
                _selectedFeature != Feat.ocr) {
              _startDocumentDetectionStream();
            }
          }),
        );
      }
    }
  }

  /// Гарантирует, что камера готова к использованию. Вызывается после
  /// возврата из инструментальных экранов — там image_picker открывал
  /// системную галерею и мог уронить контроллер.
  Future<void> _ensureCameraReady() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (_selectedFeature == Feat.qrScanner && !_isQrStreaming) {
        _startBarcodeScanning();
      }
      return;
    }
    if (_isInitializingCamera) return;
    await _initializeCamera();
    if (!mounted) return;
    if (_selectedFeature == Feat.qrScanner) {
      unawaited(_startBarcodeScanning());
    } else if (_selectedFeature != Feat.translate && _selectedFeature != Feat.ocr) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
    final sessionId = ++_cameraSessionId;

    try {
      final previousController = _cameraController;
      _cameraController = null;
      _isQrStreaming = false;
      _isDocumentDetectionStreaming = false;
      _isDocumentFrameBusy = false;
      _documentFrameCounter = 0;
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

  void _setCaptureModeManual() {
    _cancelAutoCapture();
    setState(() {
      captureModeController.setCaptureMode("Вручную");
      _isDocumentDetected = false;
      captureModeController.resetDetectionState();
    });
    unawaited(_stopLiveDocumentDetection());
  }

  void _setCaptureModeAutoInline() {
    _cancelAutoCapture();
    setState(() {
      captureModeController.setCaptureMode("Автоматически");
      captureModeController.resetDetectionState();
      _isDocumentDetected = false;
      _isScanning = false;
      captureModeController.isScanning = false;
    });

    _startDocumentDetectionStream();
  }

  void _startDocumentDetectionStream() {
    if (_selectedFeature == Feat.qrScanner) return;

    final feature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    final bool isDocumentMode = _isGuidedCameraFeature(feature);

    if (captureModeController.captureMode == 'Вручную') {
      _cancelAutoCapture();
      captureModeController.resetDetectionState();
      setState(() => _isDocumentDetected = false);
      unawaited(_stopLiveDocumentDetection());
      return;
    }

    _quadFoundFrames = 0;
    _quadLostFrames = 0;
    captureModeController.startDetectionStream(
      isDocumentMode: isDocumentMode,
      onDetectionChanged: (detected) {
        if (mounted) setState(() => _isDocumentDetected = detected);
      },
      animationController: _detectionAnimationController,
    );

    if (isDocumentMode) {
      unawaited(_startLiveDocumentDetection());
    } else {
      unawaited(_stopLiveDocumentDetection());
    }
  }

  Future<void> _startLiveDocumentDetection() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isDocumentDetectionStreaming || _isQrStreaming) return;

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      _isDocumentDetectionStreaming = true;
      _isDocumentFrameBusy = false;
      _documentFrameCounter = 0;
      await controller.startImageStream(_processDocumentDetectionFrame);
    } catch (e) {
      _isDocumentDetectionStreaming = false;
      debugPrint('Ошибка запуска стрима детекции документа: $e');
    }
  }

  Future<void> _stopLiveDocumentDetection() async {
    final controller = _cameraController;
    if (!_isDocumentDetectionStreaming) return;
    _isDocumentDetectionStreaming = false;
    _isDocumentFrameBusy = false;
    _documentFrameCounter = 0;
    _photoQuad.value = null; // рамка живого контура гаснет при остановке стрима
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Ошибка остановки стрима детекции документа: $e');
    }
  }

  /// Покадровая стабилизация детекции с гистерезисом: «найден» — только
  /// после [_kQuadStable] устойчивых кадров подряд, «потерян» — после
  /// [_kQuadLost]. Между порогами держим текущее состояние.
  bool _stabilizedDetection(bool matchThisFrame) {
    if (matchThisFrame) {
      _quadFoundFrames++;
      _quadLostFrames = 0;
    } else {
      _quadLostFrames++;
      _quadFoundFrames = 0;
    }
    if (_quadFoundFrames >= _kQuadStable) return true;
    if (_quadLostFrames >= _kQuadLost) return false;
    return _isDocumentDetected; // держим текущее (гистерезис)
  }

  Future<void> _processDocumentDetectionFrame(CameraImage image) async {
    if (!_isDocumentDetectionStreaming || _isDocumentFrameBusy || !mounted) {
      return;
    }

    _documentFrameCounter = (_documentFrameCounter + 1) % 3;
    if (_documentFrameCounter != 0) return;

    final featureName = _selectedFeature;
    _isDocumentFrameBusy = true;
    try {
      // Эвристик распознавания стороны (_idSideWarningForFrame) ложно
      // принимал ЛИЦЕВУЮ сторону за обратную («Нужна лицевая сторона») и
      // блокировал автоснимок. Детекцию по нему больше не гейтим — снимаем
      // любую сторону, которую показал пользователь.
      // Живой контур фото обновляем КАЖДЫЙ обработанный кадр (до early-return),
      // чтобы рамка непрерывно следовала за фотографией.
      final quadFound = _updatePhotoQuad(image, featureName);
      final bool detected;
      if (_isRestorePhotoFeature(featureName) ||
          _isRemoveWatermarkFeature(featureName) ||
          _isEcoFeature(featureName)) {
        // Фоторежимы (вкл. эко-упаковку): только реальный четырёхугольник —
        // без ложных автоснимков эвристики на фактурном фоне (ковёр/стол).
        detected = quadFound;
      } else if (_isDocumentSheetFeature(featureName)) {
        // Документ: только реальный четырёхугольник (без ложной эвристики на
        // фактурном фоне/экране) + стабилизация по кадрам и гистерезис — лист
        // считается «найден» лишь после нескольких устойчивых кадров, а теряется
        // тоже не мгновенно. Это убирает дрожь и ранние/ложные автоснимки.
        detected = _stabilizedDetection(quadFound);
      } else if (_isIdOrPassportFeature(featureName)) {
        // Паспорт/ID: только реальный четырёхугольник с геометрической
        // валидацией (аспект/позиция/размер — внутри _updatePhotoQuad) и
        // покадровой стабилизацией. Старая эвристика линий по зонам рамки
        // здесь не используется: она ждёт документ на всю ширину рамки и
        // отсекает, например, вертикальную страницу паспорта, а на фактурном
        // фоне (ковёр/пол), наоборот, давала ложные срабатывания.
        detected = _stabilizedDetection(quadFound);
      } else {
        detected = _detectDocumentContour(image, featureName: featureName);
      }
      if (!mounted || !_isDocumentDetectionStreaming) return;
      if (detected == _isDocumentDetected) return;

      captureModeController.isDocumentDetected = detected;
      captureModeController.detectionWarning = null;
      if (detected) {
        _detectionAnimationController.forward(from: 0.0);
        // Не снимаем, пока ждём, что прошлую сторону уберут из кадра.
        if (!_awaitDocumentExit) {
          _scheduleAutoCapture();
        }
      } else {
        // Карта пропала из кадра — можно снимать следующую сторону.
        _awaitDocumentExit = false;
        _cancelAutoCapture();
        _detectionAnimationController.reverse(
          from: _detectionAnimationController.value,
        );
      }
      setState(() => _isDocumentDetected = detected);
    } catch (e) {
      debugPrint('Ошибка анализа контура документа: $e');
    } finally {
      _isDocumentFrameBusy = false;
    }
  }

  /// Соотношение сторон превью (портретное w/h). previewSize пакет camera
  /// отдаёт в landscape, поэтому в портрете стороны меняются местами — как и
  /// в [_buildAspectCorrectPreview]. Нужно painter'у для cover-маппинга.
  double? get _previewAspect {
    final size = _cameraController?.value.previewSize;
    if (size == null) return null;
    return size.height / size.width;
  }

  /// Обновляет живой контур фото для фоторежимов. Семплит кадр в
  /// портретный luma чуть большего разрешения и ищет четырёхугольник; результат
  /// сглаживается EMA по упорядоченным углам, чтобы рамка не дёргалась.
  /// Возвращает true, если найден реальный четырёхугольник фото. Для фоторежимов
  /// («Восстановить», «Убрать пятна») это и есть сигнал детекции — заодно
  /// рисуется живой контур.
  bool _updatePhotoQuad(CameraImage image, String featureName) {
    if (!_isRestorePhotoFeature(featureName) &&
        !_isRemoveWatermarkFeature(featureName) &&
        !_isEcoFeature(featureName) &&
        !_isDocumentSheetFeature(featureName) &&
        !_isIdOrPassportFeature(featureName)) {
      return false;
    }

    // Документ — «пустоватый» лист: выше разрешение детекции + мягче пороги
    // Canny, чтобы граница листа/текст зарегистрировались (на 180px было 0).
    // Паспорт/ID тоже детектим на повышенном разрешении: документ занимает
    // рамку-трафарет и его края должны регистрироваться надёжно.
    final bool isDoc = _isDocumentSheetFeature(featureName);
    final bool isIdPass = _isIdOrPassportFeature(featureName);
    final int targetWidth = (isDoc || isIdPass) ? 300 : 180;
    final int targetHeight = ((targetWidth * image.width) / image.height)
        .round()
        .clamp(160, 540);
    final gray = _samplePortraitLuma(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    // Паспортные страницы — светлые/«пустоватые», как лист документа.
    // Для паспорта/ID берём ВСЕХ кандидатов и выбираем похожего на документ:
    // самый большой прямоугольник сцены — часто пол/ковёр, а не документ.
    List<Offset>? quad;
    if (isIdPass) {
      final candidates = detectPhotoQuads(
        gray,
        targetWidth,
        targetHeight,
        lowContrast: true,
      );
      for (final candidate in candidates) {
        if (_quadLooksLikeFramedDocument(candidate, image, featureName)) {
          quad = candidate;
          break;
        }
      }
    } else {
      quad = detectPhotoQuad(
        gray,
        targetWidth,
        targetHeight,
        lowContrast: isDoc,
      );
    }

    if ((_quadDiagCounter++ % 12) == 0) {
      debugPrint(
        'PhotoQuad: aspect=${_previewAspect?.toStringAsFixed(3)} '
        'quad=${quad == null ? "—" : "найден"} '
        'res=${targetWidth}x$targetHeight',
      );
    }

    if (quad == null) {
      _photoQuad.value = null;
      return false;
    }
    // Локальная non-null копия: промоушен nullable-переменной не действует
    // внутри замыкания List.generate ниже.
    final resolvedQuad = quad;

    final prev = _photoQuad.value;
    if (prev != null && prev.length == 4) {
      const double a = 0.4; // вес нового кадра в сглаживании
      _photoQuad.value = List<Offset>.generate(
        4,
        (i) => Offset(
          prev[i].dx + (resolvedQuad[i].dx - prev[i].dx) * a,
          prev[i].dy + (resolvedQuad[i].dy - prev[i].dy) * a,
        ),
        growable: false,
      );
    } else {
      _photoQuad.value = resolvedQuad;
    }
    return true;
  }

  /// Проверяет, что найденный квад геометрически похож на паспорт/ID-карту,
  /// лежащую в рамке-трафарете. [quad] — [tl,tr,br,bl] в нормализованных
  /// координатах портретного кадра сенсора.
  bool _quadLooksLikeFramedDocument(
    List<Offset> quad,
    CameraImage image,
    String featureName,
  ) {
    if (quad.length != 4) return false;
    final tl = quad[0], tr = quad[1], br = quad[2], bl = quad[3];

    double dist(Offset a, Offset b) => (a - b).distance;
    final topLen = dist(tl, tr);
    final bottomLen = dist(bl, br);
    final leftLen = dist(tl, bl);
    final rightLen = dist(tr, br);
    if (topLen <= 0 || bottomLen <= 0 || leftLen <= 0 || rightLen <= 0) {
      return false;
    }

    // Противоположные стороны сопоставимы — иначе это не прямоугольник
    // в перспективе, а случайный контур.
    double ratio(double a, double b) => a > b ? a / b : b / a;
    if (ratio(topLen, bottomLen) > 1.45 || ratio(leftLen, rightLen) > 1.45) {
      return false;
    }

    // Физический аспект: нормализованные координаты растянуты по осям кадра,
    // поэтому ширину переводим в единицы высоты через аспект портретного
    // кадра (W/H = image.height / image.width, т.к. previewSize — landscape).
    final double frameWOverH = image.height / image.width;
    final widthPhys = (topLen + bottomLen) / 2 * frameWOverH;
    final heightPhys = (leftLen + rightLen) / 2;
    if (heightPhys <= 0) return false;
    final aspect = widthPhys / heightPhys;

    // Правдоподобный аспект документа в ЛЮБОЙ ориентации: одиночная страница
    // паспорта вертикально ~0.70, разворот ~1.42, ID-1 карта 1.586 (или 0.63
    // вертикально). Допуск на перспективу/наклон — широкий; отсекаются лишь
    // вытянутые полосы (стыки половиц, край ковра).
    if (aspect < 0.5 || aspect > 2.4) return false;

    // Центр по вертикали — в зоне рамки-трафарета (см. _frameSpecsForFeature).
    final centerY = (tl.dy + tr.dy + br.dy + bl.dy) / 4;
    final bool isPassport = featureName == Feat.passport;
    final double zoneTop = isPassport ? 0.10 : 0.15;
    final double zoneBottom = isPassport ? 0.62 : 0.68;
    if (centerY < zoneTop || centerY > zoneBottom) return false;

    // Размер: документ занимает заметную часть рамки, но не весь экран.
    final heightNorm = (leftLen + rightLen) / 2;
    if (heightNorm < 0.08 || heightNorm > 0.58) return false;

    return true;
  }

  void _scheduleAutoCapture() {
    if (_autoCaptureTimer?.isActive == true ||
        _isScanning ||
        captureModeController.captureMode != 'Автоматически') {
      return;
    }

    final feature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    if (!_isGuidedCameraFeature(feature)) return;

    _autoCaptureFeature = _selectedFeature;
    _autoCaptureSide = _currentSide;
    _autoCapturePageMode = _pageMode;
    _autoCaptureTimer = Timer(const Duration(milliseconds: 950), () {
      unawaited(
        _runAutoCapture(
          feature: _autoCaptureFeature,
          side: _autoCaptureSide,
          pageMode: _autoCapturePageMode,
        ),
      );
    });
  }

  void _cancelAutoCapture() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _autoCaptureFeature = null;
    _autoCaptureSide = null;
    _autoCapturePageMode = null;
  }

  Future<void> _runAutoCapture({
    required String? feature,
    required String? side,
    required String? pageMode,
  }) async {
    _autoCaptureTimer = null;
    if (!mounted ||
        _isScanning ||
        !_isDocumentDetected ||
        captureModeController.detectionWarning != null ||
        captureModeController.captureMode != 'Автоматически' ||
        feature != _selectedFeature ||
        side != _currentSide ||
        pageMode != _pageMode) {
      return;
    }

    await _stopLiveDocumentDetection();
    if (!mounted ||
        _isScanning ||
        captureModeController.captureMode != 'Автоматически' ||
        feature != _selectedFeature ||
        side != _currentSide ||
        pageMode != _pageMode) {
      _startDocumentDetectionStream();
      return;
    }

    await _takePicture(bypassCaptureMode: true);
  }

  // Временно отключён: ложно блокировал автоснимок лицевой стороны.
  // ignore: unused_element
  String? _idSideWarningForFrame(CameraImage image) {
    if (_selectedFeature != Feat.idCard ||
        _currentSide != 'Лицевая') {
      return null;
    }

    final portraitWidth = image.height;
    final portraitHeight = image.width;
    if (portraitWidth < 40 || portraitHeight < 40) return null;

    const targetWidth = 96;
    final targetHeight = ((portraitHeight / portraitWidth) * targetWidth)
        .round()
        .clamp(120, 180);
    final gray = _samplePortraitLuma(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );

    final looksBackSide = _frameSpecsForFeature(Feat.idCard).any(
      (spec) => _looksLikeIdBackSide(gray, targetWidth, targetHeight, spec),
    );

    return looksBackSide ? 'Нужна лицевая сторона' : null;
  }

  bool _looksLikeIdBackSide(
    List<int> gray,
    int targetWidth,
    int targetHeight,
    _DocumentFrameSpec spec,
  ) {
    final left = (spec.left * targetWidth).round().clamp(4, targetWidth - 5);
    final right = (spec.right * targetWidth).round().clamp(
      left + 8,
      targetWidth - 4,
    );
    final top = (spec.top * targetHeight).round().clamp(4, targetHeight - 5);
    final bottom = (spec.bottom * targetHeight).round().clamp(
      top + 8,
      targetHeight - 4,
    );
    final width = right - left;
    final height = bottom - top;
    if (width < 28 || height < 18) return false;

    final cropMean = _regionMean(
      gray,
      targetWidth,
      left,
      top,
      width,
      height,
      targetHeight,
    );
    final darkThreshold = (cropMean - 42).clamp(58, 138).round();

    int mrzLikeRows = 0;
    int barcodeLikeRows = 0;
    double lowerDarkDensitySum = 0;
    int lowerRowCount = 0;

    final lowerStart = top + (height * 0.50).round();
    for (int y = lowerStart; y < bottom - 1; y++) {
      int darkCount = 0;
      int transitions = 0;
      bool? previousDark;

      for (int x = left + 2; x < right - 2; x++) {
        final isDark = gray[y * targetWidth + x] < darkThreshold;
        if (isDark) darkCount++;
        if (previousDark != null && previousDark != isDark) {
          transitions++;
        }
        previousDark = isDark;
      }

      final density = darkCount / width;
      lowerDarkDensitySum += density;
      lowerRowCount++;

      if (density > 0.10 && density < 0.46 && transitions > 18) {
        mrzLikeRows++;
      }
      if (density > 0.24 && transitions > 10) {
        barcodeLikeRows++;
      }
    }

    final lowerDarkDensity = lowerRowCount == 0
        ? 0.0
        : lowerDarkDensitySum / lowerRowCount;

    return mrzLikeRows >= 5 ||
        (mrzLikeRows >= 3 && barcodeLikeRows >= 4) ||
        (barcodeLikeRows >= 8 && lowerDarkDensity > 0.14);
  }

  bool _detectDocumentContour(
    CameraImage image, {
    required String featureName,
  }) {
    final portraitWidth = image.height;
    final portraitHeight = image.width;
    if (portraitWidth < 40 || portraitHeight < 40) return false;

    const targetWidth = 96;
    final targetHeight = ((portraitHeight / portraitWidth) * targetWidth)
        .round()
        .clamp(120, 180);
    final gray = _samplePortraitLuma(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );

    final specs = _frameSpecsForFeature(featureName);
    return specs.any(
      (spec) => _matchesDocumentFrame(
        gray,
        targetWidth,
        targetHeight,
        spec,
        featureName: featureName,
      ),
    );
  }

  bool _matchesDocumentFrame(
    List<int> gray,
    int targetWidth,
    int targetHeight,
    _DocumentFrameSpec spec, {
    required String featureName,
  }) {
    final left = (spec.left * targetWidth).round().clamp(4, targetWidth - 5);
    final right = (spec.right * targetWidth).round().clamp(
      left + 8,
      targetWidth - 4,
    );
    final top = (spec.top * targetHeight).round().clamp(4, targetHeight - 5);
    final bottom = (spec.bottom * targetHeight).round().clamp(
      top + 8,
      targetHeight - 4,
    );

    final leftScore = _verticalLineScore(
      gray,
      targetWidth,
      targetHeight,
      left,
      top,
      bottom,
    );
    final rightScore = _verticalLineScore(
      gray,
      targetWidth,
      targetHeight,
      right,
      top,
      bottom,
    );
    final topScore = _horizontalLineScore(
      gray,
      targetWidth,
      targetHeight,
      top,
      left,
      right,
    );
    final bottomScore = _horizontalLineScore(
      gray,
      targetWidth,
      targetHeight,
      bottom,
      left,
      right,
    );
    final globalEdge = _globalEdgeMean(gray, targetWidth, targetHeight);
    final innerVariance = _regionVariance(
      gray,
      targetWidth,
      ((left + right) / 2 - (right - left) * 0.28).round(),
      ((top + bottom) / 2 - (bottom - top) * 0.28).round(),
      ((right - left) * 0.56).round(),
      ((bottom - top) * 0.56).round(),
      targetHeight,
    );
    final innerMean = _regionMean(
      gray,
      targetWidth,
      ((left + right) / 2 - (right - left) * 0.26).round(),
      ((top + bottom) / 2 - (bottom - top) * 0.26).round(),
      ((right - left) * 0.52).round(),
      ((bottom - top) * 0.52).round(),
      targetHeight,
    );
    final outerMean =
        <double>[
          _regionMean(
            gray,
            targetWidth,
            left - ((right - left) * 0.18).round(),
            top,
            ((right - left) * 0.14).round(),
            bottom - top,
            targetHeight,
          ),
          _regionMean(
            gray,
            targetWidth,
            right + 2,
            top,
            ((right - left) * 0.14).round(),
            bottom - top,
            targetHeight,
          ),
          _regionMean(
            gray,
            targetWidth,
            left,
            top - ((bottom - top) * 0.18).round(),
            right - left,
            ((bottom - top) * 0.14).round(),
            targetHeight,
          ),
          _regionMean(
            gray,
            targetWidth,
            left,
            bottom + 2,
            right - left,
            ((bottom - top) * 0.14).round(),
            targetHeight,
          ),
        ].fold<double>(0, (sum, value) => sum + value) /
        4;

    final bool isDocumentSheet =
        featureName == Feat.document || featureName == Feat.plus10Pages;
    final minVertical = globalEdge * (isDocumentSheet ? 1.62 : 1.45);
    final minHorizontal = globalEdge * (isDocumentSheet ? 1.52 : 1.35);
    final frameScores = [leftScore, rightScore, topScore, bottomScore];
    final strongLineCount = [
      leftScore > minVertical,
      rightScore > minVertical,
      topScore > minHorizontal,
      bottomScore > minHorizontal,
    ].where((strong) => strong).length;
    final averageFrameScore =
        frameScores.fold<double>(0, (sum, value) => sum + value) /
        frameScores.length;
    final hasStrongLines = isDocumentSheet
        ? strongLineCount >= 4 && averageFrameScore > globalEdge * 1.58
        : strongLineCount >= 3 && averageFrameScore > globalEdge * 1.45;
    final areaRatio =
        ((right - left) * (bottom - top)) / (targetWidth * targetHeight);
    final hasPlainDocumentSurface =
        (innerVariance < 1500 && innerMean > 118) ||
        (innerMean > 92 && innerMean - outerMean > 16);
    final hasDetailedDocumentSurface = innerMean > 122 && innerVariance < 5200;
    final hasDocumentSurface =
        hasPlainDocumentSurface || hasDetailedDocumentSurface;

    // Карта всегда заметно ЯРЧЕ окружения (карта светлая, рука/стол/ковёр
    // темнее). Без этого условия детектор ложно срабатывал на однородном
    // ярком фоне и снимал «документ», когда карты в кадре нет.
    final hasContrast = innerMean - outerMean > (isDocumentSheet ? 18 : 14);

    return hasStrongLines &&
        areaRatio > (isDocumentSheet ? 0.24 : 0.18) &&
        hasDocumentSurface &&
        hasContrast;
  }

  // Зоны live-детектора должны совпадать с рамками-трафаретами
  // (DocumentGuideFrame в id_card_camera/passport_camera): пользователь
  // кладёт документ в рамку, и детектор ищет края именно там. Вертикальные
  // границы посчитаны из геометрии рамки (widthFactor 0.85, aspect карты
  // 1.586 / паспорта 1.42, verticalAlignment -0.25 / -0.42) для экранов
  // с соотношением сторон 1.9–2.3; три варианта дают допуск.
  List<_DocumentFrameSpec> _frameSpecsForFeature(String featureName) {
    switch (featureName) {
      case Feat.idCard:
        // Рамка ID-карты: верх ~0.27–0.29 H, низ ~0.52–0.55 H.
        return const [
          _DocumentFrameSpec(left: 0.08, right: 0.92, top: 0.27, bottom: 0.53),
          _DocumentFrameSpec(left: 0.05, right: 0.95, top: 0.24, bottom: 0.57),
          _DocumentFrameSpec(left: 0.10, right: 0.90, top: 0.30, bottom: 0.50),
        ];
      case Feat.document:
      case Feat.plus10Pages:
        return const [
          _DocumentFrameSpec(left: 0.11, right: 0.89, top: 0.12, bottom: 0.62),
          _DocumentFrameSpec(left: 0.08, right: 0.92, top: 0.08, bottom: 0.70),
          _DocumentFrameSpec(left: 0.06, right: 0.94, top: 0.06, bottom: 0.80),
        ];
      case Feat.passport:
      default:
        // Рамка паспорта: верх ~0.20–0.22 H, низ ~0.48–0.51 H.
        return const [
          _DocumentFrameSpec(left: 0.08, right: 0.92, top: 0.20, bottom: 0.49),
          _DocumentFrameSpec(left: 0.06, right: 0.94, top: 0.17, bottom: 0.53),
          _DocumentFrameSpec(left: 0.10, right: 0.90, top: 0.23, bottom: 0.46),
        ];
    }
  }

  List<int> _samplePortraitLuma(
    CameraImage image, {
    required int targetWidth,
    required int targetHeight,
  }) {
    final result = List<int>.filled(targetWidth * targetHeight, 0);

    if (Platform.isIOS && image.planes.length == 1) {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final bytesPerRow = plane.bytesPerRow;
      for (int y = 0; y < targetHeight; y++) {
        final srcPortraitY = ((y / (targetHeight - 1)) * (image.width - 1))
            .round();
        for (int x = 0; x < targetWidth; x++) {
          final srcPortraitX = ((x / (targetWidth - 1)) * (image.height - 1))
              .round();
          final srcX = srcPortraitY;
          final srcY = image.height - 1 - srcPortraitX;
          final offset = srcY * bytesPerRow + srcX * 4;
          final b = bytes[offset];
          final g = bytes[offset + 1];
          final r = bytes[offset + 2];
          result[y * targetWidth + x] = (0.114 * b + 0.587 * g + 0.299 * r)
              .round();
        }
      }
      return result;
    }

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;

    for (int y = 0; y < targetHeight; y++) {
      final srcPortraitY = ((y / (targetHeight - 1)) * (image.width - 1))
          .round();
      for (int x = 0; x < targetWidth; x++) {
        final srcPortraitX = ((x / (targetWidth - 1)) * (image.height - 1))
            .round();
        final srcX = srcPortraitY;
        final srcY = image.height - 1 - srcPortraitX;
        result[y * targetWidth + x] =
            bytes[srcY * rowStride + srcX * pixelStride];
      }
    }
    return result;
  }

  double _verticalLineScore(
    List<int> gray,
    int width,
    int height,
    int x,
    int y0,
    int y1,
  ) {
    final samples = <int>[];
    for (int y = y0 + 1; y < y1 - 1; y += 2) {
      final left = gray[y * width + (x - 2).clamp(0, width - 1)];
      final right = gray[y * width + (x + 2).clamp(0, width - 1)];
      samples.add((right - left).abs());
    }
    return _topSamplesMean(samples);
  }

  double _horizontalLineScore(
    List<int> gray,
    int width,
    int height,
    int y,
    int x0,
    int x1,
  ) {
    final samples = <int>[];
    for (int x = x0 + 1; x < x1 - 1; x += 2) {
      final top = gray[(y - 2).clamp(0, height - 1) * width + x];
      final bottom = gray[(y + 2).clamp(0, height - 1) * width + x];
      samples.add((bottom - top).abs());
    }
    return _topSamplesMean(samples);
  }

  double _topSamplesMean(List<int> samples) {
    if (samples.isEmpty) return 0;
    samples.sort((a, b) => b.compareTo(a));
    final takeCount = (samples.length * 0.6).round().clamp(1, samples.length);
    final top = samples.take(takeCount);
    return top.fold<int>(0, (sum, v) => sum + v) / takeCount;
  }

  double _globalEdgeMean(List<int> gray, int width, int height) {
    var sum = 0;
    var count = 0;
    for (int y = 2; y < height - 2; y += 4) {
      for (int x = 2; x < width - 2; x += 4) {
        final dx = (gray[y * width + x + 2] - gray[y * width + x - 2]).abs();
        final dy = (gray[(y + 2) * width + x] - gray[(y - 2) * width + x])
            .abs();
        sum += dx + dy;
        count += 2;
      }
    }
    if (count == 0) return 0;
    return sum / count;
  }

  double _regionVariance(
    List<int> gray,
    int width,
    int x,
    int y,
    int boxWidth,
    int boxHeight,
    int height,
  ) {
    final startX = x.clamp(0, width - 1);
    final startY = y.clamp(0, height - 1);
    final endX = (startX + boxWidth).clamp(startX + 1, width);
    final endY = (startY + boxHeight).clamp(startY + 1, height);

    double sum = 0;
    double sumSq = 0;
    int count = 0;
    for (int yy = startY; yy < endY; yy += 2) {
      for (int xx = startX; xx < endX; xx += 2) {
        final value = gray[yy * width + xx].toDouble();
        sum += value;
        sumSq += value * value;
        count++;
      }
    }
    if (count == 0) return double.infinity;
    final mean = sum / count;
    return (sumSq / count) - (mean * mean);
  }

  double _regionMean(
    List<int> gray,
    int width,
    int x,
    int y,
    int boxWidth,
    int boxHeight,
    int height,
  ) {
    final startX = x.clamp(0, width - 1);
    final startY = y.clamp(0, height - 1);
    final endX = (startX + boxWidth).clamp(startX + 1, width);
    final endY = (startY + boxHeight).clamp(startY + 1, height);

    double sum = 0;
    int count = 0;
    for (int yy = startY; yy < endY; yy += 2) {
      for (int xx = startX; xx < endX; xx += 2) {
        sum += gray[yy * width + xx];
        count++;
      }
    }

    if (count == 0) return 0;
    return sum / count;
  }

  void _resetTwoPageState() {
    _firstCapturedImage = null;
    _secondCapturedImage = null;
    _passportBatch = [];
    _awaitDocumentExit = false;
  }

  void _resetIdCardState() {
    _idCardFrontImage = null;
    _idCardBackImage = null;
    _currentSide = 'Лицевая';
    _awaitDocumentExit = false;
  }

  void _resetMultiPageState() {
    _multiPageBatch = [];
  }

  Future<void> _onFinishBatch() async {
    if (_multiPageBatch.isEmpty) {
      AppNotification.show(
        context,
        message: AppLocalizations.of(context).camBatchEmpty,
        type: NotificationType.info,
      );
      return;
    }

    // «Готово» ведёт сразу к выбору формата (минуя превью и экран правки).
    // Страницы уже авто-обрезаны при захвате → editStates не нужны (null =
    // берём файлы как есть). На успешном сохранении success-экран сам сносит
    // стек камеры; на отмене — возвращаемся сюда, батч сохраняется.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveOptionsScreen(
          sourceFilePaths: _multiPageBatch.map((f) => f.path).toList(),
          editStates: null,
        ),
      ),
    );

    if (!mounted) return;
    if (_selectedFeature != Feat.translate) {
      _startDocumentDetectionStream();
    }
  }

  void _onClearBatch() {
    _resetMultiPageState();
    if (_selectedFeature != Feat.translate) {
      _startDocumentDetectionStream();
    }
    AppNotification.show(
      context,
      message: AppLocalizations.of(context).camBatchCleared,
      type: NotificationType.info,
    );
  }

  Future<List<String>> _resolveScannedImagePaths(dynamic rawResult) async {
    if (rawResult == null) return const [];

    if (rawResult is List) {
      return rawResult
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
    }

    if (rawResult is String && rawResult.isNotEmpty) {
      return [rawResult];
    }

    if (rawResult is Map) {
      final dynamic uriField =
          rawResult['Uri'] ?? rawResult['uri'] ?? rawResult['uris'];
      final List<String> uriStrings;

      if (uriField is List) {
        uriStrings = uriField.whereType<String>().toList();
      } else if (uriField is String) {
        uriStrings = RegExp(
          r'(content://[^,\]\s}]+|file://[^,\]\s}]+)',
        ).allMatches(uriField).map((m) => m.group(0)!).toList();
      } else {
        uriStrings = const [];
      }

      if (uriStrings.isEmpty) return const [];

      final copied = await _nativeBridgeChannel.invokeMethod<List<dynamic>>(
        'copyContentUrisToCache',
        {'uris': uriStrings},
      );

      return (copied ?? const [])
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toList();
    }

    return const [];
  }

  Future<List<XFile>> _scanImagesWithNativeScanner({
    required int pageLimit,
  }) async {
    final dynamic rawResult = await FlutterDocScanner()
        .getScannedDocumentAsImages(page: pageLimit);
    final paths = await _resolveScannedImagePaths(rawResult);
    return paths.map(XFile.new).toList();
  }

  Future<XFile> _autoCropPassportXFile(XFile file) async {
    final croppedFile = await PassportScanner.autoCrop(File(file.path));
    return XFile(croppedFile.path);
  }

  Future<XFile> _autoCropDocumentXFile(XFile file) async {
    final croppedFile = await DocumentScanner.autoCrop(File(file.path));
    return XFile(croppedFile.path);
  }

  int get _passportTargetPageCount {
    final match = RegExp(r'\d+').firstMatch(_pageMode);
    final parsed = int.tryParse(match?.group(0) ?? '');
    return (parsed ?? 1).clamp(1, 10);
  }

  String _passportPageModeLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (count == 1) return '1 страница';
    if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) {
      return '$count страницы';
    }
    return '$count страниц';
  }

  void _setPassportPageCount(int count) {
    setState(() => _pageMode = _passportPageModeLabel(count));
  }

  String _passportOverlayLabel() {
    final target = _passportTargetPageCount;
    if (_passportBatch.isNotEmpty && _passportBatch.length < target) {
      return '${_passportBatch.length + 1} из $target';
    }
    return _passportPageModeLabel(target);
  }

  /// Повторный запуск нативного скана из кнопки «Переснять». Откладываем на
  /// post-frame: иначе _startNativeAutoScan выходит по guard `_isScanning`
  /// (исходный снимок ещё висит на await Navigator.push, и флаг сканирования
  /// сбросится только после возврата из превью).
  void _restartNativeScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startNativeAutoScan());
    });
  }

  Future<void> _openBatchPreview(List<XFile> files) async {
    if (files.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiPageDocumentPreviewScreen(
          imageFiles: files,
          onRetakeAll: () {
            Navigator.pop(context);
            _restartNativeScan();
          },
          onSaveBatch: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            if (editedPaths.isNotEmpty) {
              widget.onScanCompleted?.call(editedPaths.first);
            }
          },
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isScanning = false;
        captureModeController.isScanning = false;
      });
    }
  }

  Future<void> _openRestorePhotoEditor(
    XFile imageFile, {
    bool restartDetectionOnReturn = true,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestorePhotoScreen(
          initialImagePath: imageFile.path,
          autoEnhanceOnOpen: true,
          onSaved: () => widget.onScanCompleted?.call(''),
        ),
      ),
    );

    if (restartDetectionOnReturn) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _openRemoveSpotsEditor(
    XFile imageFile, {
    required bool startInManualMode,
    required bool autoProcessOnOpen,
    bool restartDetectionOnReturn = true,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoveSpotsScreen(
          initialImagePath: imageFile.path,
          startInManualMode: startInManualMode,
          autoProcessOnOpen: autoProcessOnOpen,
          onImageSaved: () => widget.onScanCompleted?.call(''),
        ),
      ),
    );

    if (restartDetectionOnReturn) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _openRemoveWatermarkEditor(
    XFile imageFile, {
    bool autoDetectOnOpen = false,
    bool restartDetectionOnReturn = true,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoveWatermarkScreen(
          initialImagePath: imageFile.path,
          autoDetectOnOpen: autoDetectOnOpen,
          onSaved: () => widget.onScanCompleted?.call(''),
        ),
      ),
    );

    if (restartDetectionOnReturn) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _startNativeAutoScan() async {
    final feature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    final bool isDocumentMode = _isGuidedCameraFeature(feature);
    if (!isDocumentMode || _isScanning) return;

    final l10n = AppLocalizations.of(context);

    setState(() {
      _isScanning = true;
      _isDocumentDetected = false;
      captureModeController.isScanning = true;
      captureModeController.isDocumentDetected = false;
    });

    try {
      List<XFile> scannedFiles;

      if (_selectedFeature == Feat.passport) {
        final limit = _passportTargetPageCount;
        scannedFiles = await _scanImagesWithNativeScanner(pageLimit: limit);
        if (scannedFiles.isEmpty || !mounted) return;

        final passportFiles = <XFile>[];
        for (final scannedFile in scannedFiles.take(limit)) {
          passportFiles.add(await _autoCropPassportXFile(scannedFile));
          if (!mounted) return;
        }

        _passportBatch.addAll(passportFiles);

        if (_passportBatch.length >= limit) {
          final readyFiles = _passportBatch.take(limit).toList();
          await _openPreview(
            imageFiles: readyFiles,
            isTwoPage: readyFiles.length > 1,
            onRetake: () {
              Navigator.pop(context);
              _resetTwoPageState();
              _restartNativeScan();
            },
            restartDetectionOnReturn: false,
          );
          _resetTwoPageState();
          return;
        }

        AppNotification.show(
          context,
          message: l10n.camPageNofM(_passportBatch.length + 1, limit),
          type: NotificationType.success,
        );
        _restartNativeScan();
        return;
      }

      if (_selectedFeature == Feat.idCard) {
        final limit = _currentSide == 'Лицевая' ? 2 : 1;
        scannedFiles = await _scanImagesWithNativeScanner(pageLimit: limit);
        if (scannedFiles.isEmpty || !mounted) return;

        if (_currentSide == 'Лицевая' && scannedFiles.length >= 2) {
          _idCardFrontImage = scannedFiles.first;
          _idCardBackImage = scannedFiles[1];

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IdCardPhotoPreviewScreen(
                frontImage: _idCardFrontImage!,
                backImage: _idCardBackImage!,
                onRetake: () {
                  Navigator.pop(context);
                  _resetIdCardState();
                  _restartNativeScan();
                },
                onConfirm: () {
                  widget.onScanCompleted?.call(_idCardFrontImage!.path);
                },
              ),
            ),
          );

          _resetIdCardState();
          return;
        }

        if (_currentSide == 'Лицевая') {
          setState(() {
            _idCardFrontImage = scannedFiles.first;
            _currentSide = 'Обратная';
            _isScanning = false;
            captureModeController.isScanning = false;
          });
          AppNotification.show(
            context,
            message: l10n.camFrontReady,
            type: NotificationType.success,
          );
          return;
        }

        _idCardBackImage = scannedFiles.first;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IdCardPhotoPreviewScreen(
              frontImage: _idCardFrontImage!,
              backImage: _idCardBackImage!,
              onRetake: () {
                Navigator.pop(context);
                _resetIdCardState();
                _restartNativeScan();
              },
              onConfirm: () {
                widget.onScanCompleted?.call(_idCardFrontImage!.path);
              },
            ),
          ),
        );
        _resetIdCardState();
        return;
      }

      final pageLimit = _selectedFeature == Feat.document
          ? _documentTargetPageCount
          : 30;
      scannedFiles = await _scanImagesWithNativeScanner(pageLimit: pageLimit);
      if (scannedFiles.isEmpty || !mounted) return;

      final processedFiles = <XFile>[];
      for (final scannedFile in scannedFiles) {
        processedFiles.add(await _autoCropDocumentXFile(scannedFile));
        if (!mounted) return;
      }

      await _openBatchPreview(processedFiles);
    } catch (e) {
      if (mounted) {
        AppNotification.show(
          context,
          message: '${l10n.commonError}: $e',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          captureModeController.isScanning = false;
        });
      }
    }
  }

  Future<void> _takePicture({bool bypassCaptureMode = false}) async {
    _cancelAutoCapture();
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isScanning ||
        _selectedFeature == Feat.qrScanner) {
      return;
    }

    if (_selectedFeature == Feat.translate) {
      return;
    }

    final currentFeature = _features.firstWhere(
      (f) => f['name'] == _selectedFeature,
      orElse: () => _features.first,
    );
    final bool isDocumentMode = _isGuidedCameraFeature(currentFeature);
    final bool isMultiPageLimited = _selectedFeature == Feat.document;
    final bool isMultiPageUnlimited = _selectedFeature == Feat.plus10Pages;

    final l10n = AppLocalizations.of(context);
    if (!bypassCaptureMode &&
        !captureModeController.canTakePicture(isDocumentMode: isDocumentMode)) {
      AppNotification.show(
        context,
        message: l10n.camWaitingDocument,
        type: NotificationType.info,
        duration: const Duration(seconds: 2),
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

      if (_isRestorePhotoFeature(_selectedFeature)) {
        // Авто-обрезка по краям снятого фото — как у документа/ID-карты:
        // убираем стол/фон, в редактор попадает только сама фотография.
        // DocumentScanner при неуверенности возвращает оригинал, так что
        // порезать кадр он не может (square-фото просто останется целым).
        final restoreImage = await _autoCropDocumentXFile(file);
        if (!mounted) return;
        await _openRestorePhotoEditor(
          restoreImage,
          restartDetectionOnReturn: false,
        );
        if (!mounted) return;
        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();
        return;
      }

      if (_isRemoveSpotsFeature(_selectedFeature)) {
        final removeSpotsImage = await _autoCropDocumentXFile(file);
        if (!mounted) return;
        final startInManualMode =
            captureModeController.captureMode == 'Вручную';
        await _openRemoveSpotsEditor(
          removeSpotsImage,
          startInManualMode: startInManualMode,
          autoProcessOnOpen: !startInManualMode,
          restartDetectionOnReturn: false,
        );
        if (!mounted) return;
        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();
        return;
      }

      if (_isRemoveWatermarkFeature(_selectedFeature)) {
        final useAutoCrop =
            captureModeController.captureMode == 'Автоматически';
        final watermarkImage = useAutoCrop
            ? await _autoCropDocumentXFile(file)
            : file;
        if (!mounted) return;
        await _openRemoveWatermarkEditor(
          watermarkImage,
          autoDetectOnOpen: useAutoCrop,
          restartDetectionOnReturn: false,
        );
        if (!mounted) return;
        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();
        return;
      }

      if (_isEcoFeature(_selectedFeature)) {
        // Снимок упаковки → эко-анализ. Камера остаётся открытой: после
        // возврата с экрана отчёта перезапускаем детекцию.
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EcoPackagingScreen(initialImage: File(file.path)),
          ),
        );
        if (!mounted) return;
        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();
        return;
      }

      if (isMultiPageLimited || isMultiPageUnlimited) {
        final documentImage = await _autoCropDocumentXFile(file);
        if (!mounted) return;

        if (isMultiPageLimited) {
          final int maxPages = _documentTargetPageCount;
          if (_currentBatchPageCount >= maxPages) {
            AppNotification.show(
              context,
              message: l10n.camMaxPages,
              type: NotificationType.info,
            );
            _isScanning = false;
            captureModeController.isScanning = false;
            _startDocumentDetectionStream();
            return;
          }
        }

        _multiPageBatch.add(documentImage);
        setState(() {});

        _isScanning = false;
        captureModeController.isScanning = false;
        _startDocumentDetectionStream();

        AppNotification.show(
          context,
          message: l10n.camPageAdded(_multiPageBatch.length),
          type: NotificationType.success,
        );
        return;
      }

      if (_selectedFeature == Feat.idCard) {
        // Авто-обрезка карты до краёв (OpenCV) — убирает фон/руку. При
        // неудаче autoCrop вернёт исходный файл (без регресса).
        final croppedFile = await IdCardScanner.autoCrop(File(file.path));
        if (!mounted) return;
        final XFile cardImage = XFile(croppedFile.path);

        if (_currentSide == "Лицевая") {
          setState(() {
            _idCardFrontImage = cardImage;
            _currentSide = 'Обратная';
          });
          _isScanning = false;
          captureModeController.isScanning = false;
          // Ждём, пока лицевую уберут из кадра, прежде чем авто-снимать
          // обратную — даёт время перевернуть карту.
          _awaitDocumentExit = true;
          _startDocumentDetectionStream();

          AppNotification.show(
            context,
            message: l10n.camFrontReady,
            type: NotificationType.success,
          );
          return;
        }

        _idCardBackImage = cardImage;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IdCardPhotoPreviewScreen(
              frontImage: _idCardFrontImage!,
              backImage: _idCardBackImage!,
              // «Переснять» — просто закрываем превью и возвращаемся на
              // камеру в режиме «ID-карта». Сброс состояния и перезапуск
              // детекции делает код ниже (после await Navigator.push).
              onRetake: () => Navigator.pop(context),
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

      if (_selectedFeature == Feat.passport) {
        final passportImage = await _autoCropPassportXFile(file);
        if (!mounted) return;
        final targetPageCount = _passportTargetPageCount;
        _passportBatch.add(passportImage);

        if (_passportBatch.length >= targetPageCount) {
          final readyFiles = List<XFile>.from(_passportBatch);
          await _openPreview(
            imageFiles: readyFiles,
            isTwoPage: readyFiles.length > 1,
          );

          _resetTwoPageState();
          _isScanning = false;
          captureModeController.isScanning = false;
          _startDocumentDetectionStream();
          return;
        }

        _isScanning = false;
        captureModeController.isScanning = false;
        _awaitDocumentExit = true;
        _startDocumentDetectionStream();
        AppNotification.show(
          context,
          message: l10n.camPageNofM(_passportBatch.length + 1, targetPageCount),
          type: NotificationType.success,
        );
        return;
      }

      if (currentFeature['hasTwoPageMode'] == true &&
          _pageMode == "2 страницы") {
        if (_firstCapturedImage == null) {
          setState(() => _firstCapturedImage = file);
          _isScanning = false;
          captureModeController.isScanning = false;
          _startDocumentDetectionStream();
          AppNotification.show(
            context,
            message: l10n.camFirstPageReady,
            type: NotificationType.success,
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

      await _openPreview(imageFile: file, isTwoPage: false);

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

  /// Обрезка снимка перед распознаванием: пользователь выделяет только
  /// нужный фрагмент текста — точность OCR заметно выше, чем по всему кадру.
  /// Отмена обрезки = используем исходный кадр целиком.
  Future<XFile> _cropForOcr(XFile file) async {
    final l10n = AppLocalizations.of(context);
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: l10n.editCropDocTitle,
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: l10n.editCropDocTitle),
        ],
      );
      return cropped == null ? file : XFile(cropped.path);
    } catch (e) {
      debugPrint('Ошибка обрезки (OCR): $e');
      return file;
    }
  }

  /// Съёмка в режиме OCR. Детекция документа для OCR не запускается
  /// (см. условия в initState и селекторе), поэтому image-stream не
  /// активен и takePicture() не конфликтует с ним.
  Future<void> _captureForOcr() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      XFile file = await _cameraController!.takePicture();
      if (!mounted) return;
      file = await _cropForOcr(file);
      await _runOcrWith(file);
    } catch (e) {
      debugPrint('Ошибка съёмки (OCR): $e');
    }
  }

  Future<void> _pickImageForOcr() async {
    final ImagePicker picker = ImagePicker();
    XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    image = await _cropForOcr(image);
    await _runOcrWith(image);
  }

  Future<void> _openPreview({
    XFile? imageFile,
    XFile? secondImageFile,
    List<XFile>? imageFiles,
    required bool isTwoPage,
    VoidCallback? onRetake,
    bool restartDetectionOnReturn = true,
  }) async {
    final previewFiles =
        imageFiles ??
        [
          if (imageFile != null) imageFile,
          if (secondImageFile != null) secondImageFile,
        ];
    if (previewFiles.isEmpty) return;
    final normalizedPreviewFiles = isTwoPage || previewFiles.length > 1
        ? previewFiles
        : [previewFiles.first];

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoPreviewScreen(
          imageFiles: normalizedPreviewFiles,
          onRetake:
              onRetake ??
              () {
                Navigator.pop(context);
                _startDocumentDetectionStream();
              },
          onConfirm: () {
            widget.onScanCompleted?.call(normalizedPreviewFiles.first.path);
          },
        ),
      ),
    );
    if (restartDetectionOnReturn) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _pickImageFromGallery() async {
    final l10n = AppLocalizations.of(context);
    final ImagePicker picker = ImagePicker();
    final XFile? galleryImage = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (galleryImage == null) return;
    if (!mounted) return;

    if (_selectedFeature == Feat.qrScanner) return;

    if (_selectedFeature == Feat.passport) {
      final passportImage = await _autoCropPassportXFile(galleryImage);
      if (!mounted) return;

      _passportBatch.add(passportImage);
      final targetPageCount = _passportTargetPageCount;

      if (_passportBatch.length >= targetPageCount) {
        final readyFiles = List<XFile>.from(_passportBatch);
        await _openPreview(
          imageFiles: readyFiles,
          isTwoPage: readyFiles.length > 1,
        );
        _resetTwoPageState();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).camPageNofM(_passportBatch.length + 1, targetPageCount),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      _startDocumentDetectionStream();
      return;
    }

    final bool isMultiPageLimited = _selectedFeature == Feat.document;
    final bool isMultiPageUnlimited = _selectedFeature == Feat.plus10Pages;

    if (_isRestorePhotoFeature(_selectedFeature)) {
      await _openRestorePhotoEditor(galleryImage);
      return;
    }

    if (_isRemoveSpotsFeature(_selectedFeature)) {
      final startInManualMode = captureModeController.captureMode == 'Вручную';
      await _openRemoveSpotsEditor(
        galleryImage,
        startInManualMode: startInManualMode,
        autoProcessOnOpen: !startInManualMode,
      );
      return;
    }

    if (_isRemoveWatermarkFeature(_selectedFeature)) {
      await _openRemoveWatermarkEditor(
        galleryImage,
        autoDetectOnOpen: captureModeController.captureMode == 'Автоматически',
      );
      return;
    }

    if (_isEcoFeature(_selectedFeature)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              EcoPackagingScreen(initialImage: File(galleryImage.path)),
        ),
      );
      if (!mounted) return;
      _startDocumentDetectionStream();
      return;
    }

    if (isMultiPageLimited || isMultiPageUnlimited) {
      final documentImage = await _autoCropDocumentXFile(galleryImage);
      if (!mounted) return;

      if (isMultiPageLimited) {
        final int maxPages = _documentTargetPageCount;
        if (_currentBatchPageCount >= maxPages) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.camMaxPages)));
          return;
        }
      }

      _multiPageBatch.add(documentImage);
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
    final double itemCenter =
        leadingPadding + index * itemWidth + itemWidth / 2;
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
            content: Text(
              AppLocalizations.of(
                context,
              ).camCantOpenLink(string, e.runtimeType.toString()),
            ),
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
      _isDocumentDetectionStreaming = false;
      _isDocumentFrameBusy = false;
      _documentFrameCounter = 0;
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
        if (_selectedFeature == Feat.qrScanner) {
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

  bool _isPremiumFeatureName(String featureName) {
    return _premiumFeatureNames.contains(featureName);
  }

  bool _isRestorePhotoFeature(String featureName) {
    return featureName == Feat.restorePhoto;
  }

  bool _isRemoveSpotsFeature(String featureName) {
    return featureName == Feat.removeSpots;
  }

  bool _isRemoveWatermarkFeature(String featureName) {
    return featureName == Feat.removeWatermark;
  }

  bool _isEcoFeature(String featureName) {
    return featureName == Feat.eco;
  }

  bool _isDocumentSheetFeature(String featureName) {
    return featureName == Feat.document || featureName == Feat.plus10Pages;
  }

  bool _isIdOrPassportFeature(String featureName) {
    return featureName == Feat.idCard || featureName == Feat.passport;
  }

  bool _isGuidedCameraFeature(Map<String, dynamic> feature) {
    return feature['isDocument'] == true ||
        _isRestorePhotoFeature(feature['name'] as String? ?? '') ||
        _isRemoveSpotsFeature(feature['name'] as String? ?? '') ||
        _isRemoveWatermarkFeature(feature['name'] as String? ?? '') ||
        _isEcoFeature(feature['name'] as String? ?? '');
  }

  String _featureLabel(Map<String, dynamic> feature, AppLocalizations l10n) {
    switch (feature['name'] as String) {
      case Feat.passport: return l10n.camChipPassport;
      case Feat.idCard: return l10n.camChipIdCard;
      case Feat.document: return l10n.camChipDocument;
      case Feat.qrScanner: return l10n.camChipQr;
      case Feat.plus10Pages: return l10n.camChip10Pages;
      case Feat.translate: return l10n.camChipTranslate;
      case Feat.signature: return l10n.camChipSignature;
      case Feat.restorePhoto: return l10n.camChipRestore;
      case Feat.removeSpots: return l10n.camChipRemoveSpots;
      case Feat.highlight: return l10n.camChipHighlight;
      case Feat.ocr: return l10n.camChipOcr;
      case Feat.removeWatermark: return l10n.camChipNoWatermark;
      case Feat.addPassword: return l10n.camChipPassword;
      case Feat.eco: return l10n.camChipEco;
      default: return (feature['label'] ?? feature['name']) as String;
    }
  }

  bool _canUseFeature(String featureName) {
    if (!_isPremiumFeatureName(featureName)) {
      return true;
    }
    return PremiumService().isPremium;
  }

  bool _guardPremiumFeatureSelection(String featureName) {
    if (_canUseFeature(featureName)) {
      return true;
    }
    showPremiumPaywall(context, featureName);
    return false;
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

    if (icon == Icons.highlight) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HighlightScreen(onSaved: () => widget.onScanCompleted?.call('')),
        ),
      ).then(_afterToolReturn);
      return true;
    }

    if (icon == Icons.lock_outline) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddPasswordScreen(
            onSaved: () => widget.onScanCompleted?.call(''),
          ),
        ),
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
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28,
                    ),
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
                8,
                8,
                8,
                8 + MediaQuery.of(context).padding.bottom,
              ),
              color: Colors.black.withValues(alpha: 0.5),
              child: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white70,
                        size: 22,
                      ),
                      tooltip: l10n.actionDelete,
                      onPressed: _clearQrHistory,
                    ),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _qrHistory.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) =>
                            _buildQrHistoryChip(_qrHistory[i]),
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
    final l10n = AppLocalizations.of(context);
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
          final isPremiumFeature = _isPremiumFeatureName(newFeature);

          return GestureDetector(
            onTap: () {
              if (newFeature == Feat.importDocs) {
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

              if (!_guardPremiumFeatureSelection(newFeature)) {
                return;
              }

              if (_openToolFeature(feature)) {
                return;
              }

              _cancelAutoCapture();
              setState(() {
                _selectedFeature = newFeature;
                _pageMode = '1 страница';
                _resetTwoPageState();
                _resetIdCardState();
                _resetMultiPageState();

                if (_selectedFeature != Feat.qrScanner) {
                  _qrCode = null;
                }
              });

              if (newFeature == Feat.qrScanner) {
                // Камеру НЕ пересоздаём — запускаем сканирование штрихкодов
                // на уже работающем контроллере (нет мерцания). Детекцию
                // документа выключаем.
                captureModeController.detectionTimer?.cancel();
                captureModeController.resetDetectionState();
                setState(() => _isDocumentDetected = false);
                unawaited(_stopLiveDocumentDetection());

                if (_cameraController == null) {
                  unawaited(
                    _initializeCamera().then((_) {
                      if (mounted && _selectedFeature == Feat.qrScanner) {
                        _startBarcodeScanning();
                      }
                    }),
                  );
                } else {
                  // Отложенно: предыдущий вью (напр. живой перевод) диспозится
                  // только ПОСЛЕ кроссфейда AnimatedSwitcher (~260мс), и его
                  // dispose останавливает стрим. Стартуем сканер после этого.
                  Future.delayed(const Duration(milliseconds: 350), () {
                    if (mounted && _selectedFeature == Feat.qrScanner) {
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

                if (newFeature != Feat.translate && newFeature != Feat.ocr) {
                  Future.delayed(
                    const Duration(milliseconds: 500),
                    _startDocumentDetectionStream,
                  );
                } else {
                  captureModeController.resetDetectionState();
                  setState(() => _isDocumentDetected = false);
                  unawaited(_stopLiveDocumentDetection());
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
                                  color: const Color(
                                    0xFF2CA5E0,
                                  ).withValues(alpha: 0.55),
                                  blurRadius: 14,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Icon(
                              feature['icon'] ?? Icons.circle,
                              size: iconSize,
                              color: Colors.white,
                            ),
                          ),
                          if (isPremiumFeature)
                            Positioned(
                              right: isCompact ? 6 : 8,
                              top: isCompact ? 6 : 8,
                              child: Icon(
                                Icons.workspace_premium,
                                size: isCompact ? 11 : 12,
                                color: Colors.amber.shade300,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 14,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _featureLabel(feature, l10n),
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.0,
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.7),
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
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

    if (!_isCameraInitialized && _selectedFeature != Feat.translate) {
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
      Feat.passport: () => PassportCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        pageModeLabel: _passportOverlayLabel(),
        pageCount: _passportTargetPageCount,
        takePicture: _takePicture,
        setPageCount: _setPassportPageCount,
        resetTwoPageState: _resetTwoPageState,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      Feat.idCard: () => IdCardCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        currentSide: _currentSide,
        takePicture: _takePicture,
        resetIdCardState: _resetIdCardState,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      Feat.document: () => MultiPageDocumentView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        maxPages: _documentTargetPageCount,
        currentBatchPageCount: _currentBatchPageCount,
        onFinishBatch: _onFinishBatch,
        onClearBatch: _onClearBatch,
        photoQuad: _photoQuad,
        previewAspect: _previewAspect,
      ),
      Feat.plus10Pages: () => UnlimitedDocumentView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        currentBatchPageCount: _currentBatchPageCount,
        onFinishBatch: _onFinishBatch,
        onClearBatch: _onClearBatch,
      ),
      Feat.translate: () => TranslateCamera(
        cameraController: _cameraController,
        takePicture: _takePictureForTranslation,
        pickImageFromGallery: _pickImageFromGallery,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        onScanCompleted: widget.onScanCompleted,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
      ),
      Feat.restorePhoto: () => RestorePhotoCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        photoQuad: _photoQuad,
        previewAspect: _previewAspect,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      // Эко-упаковка — фото-режим авто-сканирования (как «Восстановить»),
      // но снимок уходит в эко-анализ. Переиспользуем тот же вью с зелёным
      // оверлеем и эко-заголовком.
      Feat.eco: () => RestorePhotoCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        photoQuad: _photoQuad,
        previewAspect: _previewAspect,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
        featureTitle: AppLocalizations.of(context).ecoTitle,
        featureSubtitle: AppLocalizations.of(context).ecoCameraHint,
        overlayKind: CaptureStatusOverlayKind.eco,
      ),
      Feat.removeSpots: () => RemoveSpotsCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      Feat.removeWatermark: () => RemoveWatermarkCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        photoQuad: _photoQuad,
        previewAspect: _previewAspect,
        takePicture: _takePicture,
        pickImageFromGallery: _pickImageFromGallery,
        setCaptureModeAuto: _setCaptureModeAutoInline,
        setCaptureModeManual: _setCaptureModeManual,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      Feat.ocr: () => OcrCameraView(
        cameraController: _cameraController,
        onCapture: _captureForOcr,
        onPickGallery: _pickImageForOcr,
        onBack: () => Navigator.pop(context),
        onSettings: _openSettings,
      ),
      Feat.qrScanner: () => _buildQrCodeView(),
    };

    Widget currentCameraView =
        featureViews[_selectedFeature]?.call() ??
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
    final bool showPersistentPreview =
        _isCameraInitialized && _cameraController != null;
    final bool isTranslateSelected = _selectedFeature == Feat.translate;

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
          // Оверлей режима меняется с кроссфейдом + лёгким сдвигом снизу,
          // а не мгновенно: превью камеры при этом стабильно, поэтому
          // анимируется только UI-слой (рамки, кнопки, подписи).
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.015),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey<String>(_selectedFeature),
                child: currentCameraView,
              ),
            ),
          ),
          Positioned(
            // CameraControlsBar (child-view bottom-bar) уже включает
            // SafeArea и сам встаёт на bottom:0. Селектор сидит точно над
            // ним — высота bar'а ~78 + 32 padding + safeBottom; берём
            // 110 + safeBottom как стабильный отступ.
            bottom: MediaQuery.of(context).padding.bottom + (isTranslateSelected ? 96 : 110),
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
