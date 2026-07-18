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
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:scanbot_sdk/document_api.dart' as sb_doc;
import 'package:scanbot_sdk/scanbot_sdk_ui_v2.dart' as sb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../config/scanbot_config.dart';
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
import 'remove_spots_camera_view.dart';
import 'remove_watermark_camera_view.dart';
import '../../widgets/document_guide_frame.dart' show CornerBracketsPainter;
import '../../widgets/camera_top_panel.dart';
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

/// Геометрия выреза рамки режима для ОБЩЕГО постоянного слоя рамки:
/// затемнение, уголки, силуэт и подпись рисуются в одном месте и морфятся
/// между режимами — рассинхрон затемнения и уголков невозможен.
class _CutoutSpec {
  const _CutoutSpec(
    this.aspect,
    this.widthFactor,
    this.verticalAlignment, {
    this.brackets = true,
  });

  final double aspect;
  final double widthFactor;
  final double verticalAlignment;

  /// Рисовать ли уголки-скобки (у QR своя сплошная рамка в оверлее).
  final bool brackets;
}

/// Затемнение вокруг выреза рамки для общего постоянного слоя камеры.
class _CutoutScrimPainter extends CustomPainter {
  const _CutoutScrimPainter({required this.cutout});

  final Rect cutout;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(14)));
    final scrim = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_CutoutScrimPainter oldDelegate) =>
      oldDelegate.cutout != cutout;
}

double _manualRotationFitScale(
  Rect cutout,
  double angle, {
  required bool compactLandscape,
}) {
  final cosine = math.cos(angle).abs();
  final sine = math.sin(angle).abs();
  final rotatedWidth = cutout.width * cosine + cutout.height * sine;
  final rotatedHeight = cutout.width * sine + cutout.height * cosine;
  final maxSide = math.max(cutout.width, cutout.height);
  if (rotatedWidth <= 0 || rotatedHeight <= 0) return 1;
  final fit = math.min(
    1,
    math.min(maxSide / rotatedWidth, maxSide / rotatedHeight),
  );
  // У высоких рамок фото/документа их высота после поворота становится
  // шириной и почти упирается в края экрана. Уменьшаем только горизонтальное
  // положение; вертикальная рамка сохраняет исходный размер.
  final landscapeProgress = math.sin(angle).abs();
  final landscapeScale = compactLandscape ? 1 - 0.22 * landscapeProgress : 1.0;
  return fit * landscapeScale;
}

class _RotatedPassportFramePainter extends CustomPainter {
  const _RotatedPassportFramePainter({
    required this.cutout,
    required this.angle,
    required this.color,
    required this.compactLandscape,
  });

  final Rect cutout;
  final double angle;
  final Color color;
  final bool compactLandscape;

  @override
  void paint(Canvas canvas, Size size) {
    final center = cutout.center;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    final scale = _manualRotationFitScale(
      cutout,
      angle,
      compactLandscape: compactLandscape,
    );
    final transform = Float64List.fromList([
      cosine * scale,
      sine * scale,
      0,
      0,
      -sine * scale,
      cosine * scale,
      0,
      0,
      0,
      0,
      1,
      0,
      center.dx - cosine * scale * center.dx + sine * scale * center.dy,
      center.dy - sine * scale * center.dx - cosine * scale * center.dy,
      0,
      1,
    ]);
    final rotatedCutout =
        (Path()..addRRect(
              RRect.fromRectAndRadius(cutout, const Radius.circular(14)),
            ))
            .transform(transform);
    final scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      rotatedCutout,
    );
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.32 + 0.13 * scale),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
    CornerBracketsPainter(cutout: cutout, color: color).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RotatedPassportFramePainter oldDelegate) =>
      oldDelegate.cutout != cutout ||
      oldDelegate.angle != angle ||
      oldDelegate.color != color ||
      oldDelegate.compactLandscape != compactLandscape;
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const MethodChannel _nativeBridgeChannel = MethodChannel(
    'com.aurascanner.app/native_bridge',
  );

  // Вырезы затемнения по режимам — синхронизированы с DocumentGuideFrame
  // соответствующих вью (аспект, доля ширины, вертикальное выравнивание).
  static const Map<String, _CutoutSpec> _cutoutSpecs = {
    Feat.passport: _CutoutSpec(1.42, 0.85, -0.25),
    Feat.idCard: _CutoutSpec(1.586, 0.85, -0.25),
    // Рамки крупные: статус-карточка сверху показывается временно
    // (автоскрытие) и не резервирует место постоянно.
    Feat.document: _CutoutSpec(0.71, 0.80, -0.35),
    Feat.plus10Pages: _CutoutSpec(0.71, 0.80, -0.35),
    Feat.restorePhoto: _CutoutSpec(0.75, 0.78, -0.30),
    Feat.eco: _CutoutSpec(0.75, 0.78, -0.30),
    Feat.removeWatermark: _CutoutSpec(0.75, 0.78, -0.30),
    Feat.removeSpots: _CutoutSpec(0.75, 0.78, -0.30),
    Feat.ocr: _CutoutSpec(0.95, 0.80, -0.30),
    Feat.translate: _CutoutSpec(1.18, 0.92, -0.20),
    Feat.qrScanner: _CutoutSpec(1.0, 0.66, -0.25, brackets: false),
  };

  /// Иконка-силуэт по центру выреза (null — без силуэта).
  IconData? _frameIconFor(String feature) {
    switch (feature) {
      case Feat.passport:
        return Icons.menu_book_outlined;
      case Feat.idCard:
        return Icons.badge_outlined;
      case Feat.document:
      case Feat.plus10Pages:
        return Icons.description_outlined;
      case Feat.restorePhoto:
        return Icons.photo_outlined;
      case Feat.eco:
        return Icons.eco_outlined;
      case Feat.removeWatermark:
        return Icons.auto_fix_off_outlined;
      case Feat.removeSpots:
        return Icons.cleaning_services_outlined;
      case Feat.ocr:
        return Icons.text_fields_outlined;
      default:
        return null; // перевод, QR — без силуэта
    }
  }

  /// Подпись под рамкой (null — без подписи; у перевода и QR свои панели).
  String? _frameHintFor(String feature, AppLocalizations l10n) {
    switch (feature) {
      case Feat.passport:
        return l10n.camFitPassportInFrame;
      case Feat.idCard:
        return l10n.camFitIdInFrame;
      case Feat.document:
      case Feat.plus10Pages:
        return l10n.camFitDocInFrame;
      case Feat.restorePhoto:
      case Feat.removeWatermark:
      case Feat.removeSpots:
        return l10n.camFitPhotoInFrame;
      case Feat.eco:
        return l10n.camFitPackagingInFrame;
      case Feat.ocr:
        return l10n.ocrSelectPhoto;
      default:
        return null;
    }
  }

  /// Реагирует ли рамка режима на детекцию (зелёные уголки/подпись).
  bool _frameDetectable(String feature) =>
      feature != Feat.ocr &&
      feature != Feat.translate &&
      feature != Feat.qrScanner;
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
  bool _initialCameraBootShown = false;
  static const Duration _minimumInitialBootDuration = Duration(
    milliseconds: 1400,
  );
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
  final Map<String, Rect> _autoFrameBounds = <String, Rect>{};
  Rect? _captureFrameBounds;
  String? _captureFrameFeature;
  Rect? _previousPassportFallbackBounds;
  int _passportFallbackStableFrames = 0;
  Rect? _lastPassportCaptureBounds;
  Rect? _passportFrameRect;
  double _passportManualAngle = 0;
  bool _passportRotationDragActive = false;
  double _passportRotationStartAngle = 0;
  double _passportPointerStartAngle = 0;
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
  // Ключи пилюль селектора: ширина выбранной пилюли отличается от остальных,
  // поэтому центрирование делаем через Scrollable.ensureVisible, а не
  // арифметикой фиксированной ширины тайла.
  late final List<GlobalKey> _featureKeys = List.generate(
    _features.length,
    (_) => GlobalKey(),
  );
  late String _selectedFeature;
  String _pageMode = '1 страница';

  final CaptureModeController captureModeController = CaptureModeController();
  late AnimationController _detectionAnimationController;
  // Пульс свечения подсветки выбранного режима в селекторе.
  late final AnimationController _selectorPulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);
  // Бегущая линия сканирования в рамке QR (вверх-вниз).
  late final AnimationController _qrScanLineCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  bool _isDocumentDetected = false;
  bool _isScanning = false;
  bool _isScanbotPassportActive = false;
  bool _scanbotPassportRetakeRequested = false;
  // Стабилизация детекции документа: считаем подряд кадры с найденным/потерянным
  // контуром, чтобы не реагировать на дрожь и не снимать раньше времени.
  int _quadFoundFrames = 0;
  int _quadLostFrames = 0;
  // Обработка идёт ~6 кадров/сек (каждый 5-й кадр стрима): 3 стабильных
  // кадра ≈ 0.5 с до «найден» — компенсирует более редкую обработку.
  static const int _kQuadStable = 2; // подряд кадров с контуром → «найден»
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
      if (_selectedFeature != Feat.passport &&
          _selectedFeature != Feat.translate &&
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
    _selectorPulseCtrl.dispose();
    _qrScanLineCtrl.dispose();
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
      if (_isScanbotPassportActive) return;
      // Камера могла быть выгружена, когда системная галерея/share/etc.
      // перевели приложение в фон. На resumed всегда восстанавливаем —
      // и, если активен режим QR, заново запускаем сканирование.
      if (_cameraController == null && !_isInitializingCamera) {
        unawaited(
          _initializeCamera().then((_) {
            if (!mounted) return;
            if (_selectedFeature == Feat.qrScanner) {
              unawaited(_startBarcodeScanning());
            } else if (_selectedFeature != Feat.passport &&
                _selectedFeature != Feat.translate &&
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
    } else if (_selectedFeature != Feat.translate &&
        _selectedFeature != Feat.ocr) {
      _startDocumentDetectionStream();
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
    final sessionId = ++_cameraSessionId;
    final holdInitialSplash = !_initialCameraBootShown;
    final bootStartedAt = DateTime.now();

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

      if (holdInitialSplash) {
        final elapsed = DateTime.now().difference(bootStartedAt);
        final remaining = _minimumInitialBootDuration - elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(remaining);
        }
        if (!mounted || sessionId != _cameraSessionId) {
          await controller.dispose();
          return;
        }
        _initialCameraBootShown = true;
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

    if (_selectedFeature == Feat.passport) {
      unawaited(_startScanbotPassportScan());
    } else if (_selectedFeature != Feat.translate &&
        _selectedFeature != Feat.ocr) {
      _startDocumentDetectionStream();
    } else {
      unawaited(_stopLiveDocumentDetection());
    }
  }

  void _startDocumentDetectionStream() {
    if (!_isScanning) {
      _captureFrameBounds = null;
      _captureFrameFeature = null;
    }
    if ((_selectedFeature == Feat.passport &&
            captureModeController.captureMode == 'Автоматически') ||
        _selectedFeature == Feat.qrScanner ||
        _selectedFeature == Feat.translate ||
        _selectedFeature == Feat.ocr) {
      unawaited(_stopLiveDocumentDetection());
      return;
    }

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
    _previousPassportFallbackBounds = null;
    _passportFallbackStableFrames = 0;
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

  void _updateAutoFrame(List<Offset>? quad, String featureName) {
    if (_selectedFeature != featureName ||
        !_frameDetectable(featureName) ||
        !_cutoutSpecs.containsKey(featureName) ||
        captureModeController.captureMode != 'Автоматически' ||
        quad == null ||
        quad.length != 4) {
      return;
    }

    final xs = quad.map((point) => point.dx);
    final ys = quad.map((point) => point.dy);
    final next = Rect.fromLTRB(
      xs.reduce(math.min).clamp(0.0, 1.0),
      ys.reduce(math.min).clamp(0.0, 1.0),
      xs.reduce(math.max).clamp(0.0, 1.0),
      ys.reduce(math.max).clamp(0.0, 1.0),
    );
    if (next.width < 0.16 || next.height < 0.10) return;

    final previous = _autoFrameBounds[featureName];
    if (previous != null &&
        (previous.center - next.center).distance < 0.008 &&
        (previous.width - next.width).abs() < 0.012 &&
        (previous.height - next.height).abs() < 0.012) {
      return;
    }
    if (mounted) {
      setState(() => _autoFrameBounds[featureName] = next);
    }
  }

  Rect? _mapAutoFrame(Size size, String featureName) {
    final bounds = _isScanning && _captureFrameFeature == featureName
        ? _captureFrameBounds
        : _autoFrameBounds[featureName];
    final contentAspect = _previewAspect;
    if (bounds == null || contentAspect == null) return null;

    final boxAspect = size.width / size.height;
    late final double displayWidth;
    late final double displayHeight;
    if (boxAspect > contentAspect) {
      displayWidth = size.width;
      displayHeight = size.width / contentAspect;
    } else {
      displayHeight = size.height;
      displayWidth = size.height * contentAspect;
    }
    final dx = (size.width - displayWidth) / 2;
    final dy = (size.height - displayHeight) / 2;
    return Rect.fromLTRB(
      dx + bounds.left * displayWidth,
      dy + bounds.top * displayHeight,
      dx + bounds.right * displayWidth,
      dy + bounds.bottom * displayHeight,
    ).inflate(6);
  }

  Rect _quadBounds(List<Offset> quad) {
    final xs = quad.map((point) => point.dx);
    final ys = quad.map((point) => point.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  bool _passportGeometryIsStable(List<Offset> quad) {
    final next = _quadBounds(quad);
    final previous = _previousPassportFallbackBounds;
    if (previous != null &&
        (previous.center - next.center).distance < 0.018 &&
        (previous.width - next.width).abs() < 0.035 &&
        (previous.height - next.height).abs() < 0.035) {
      _passportFallbackStableFrames++;
    } else {
      _passportFallbackStableFrames = 1;
    }
    _previousPassportFallbackBounds = next;
    return _passportFallbackStableFrames >= 3;
  }

  bool _unlockPassportAfterPageChange(Rect? current) {
    final previous = _lastPassportCaptureBounds;
    if (!_awaitDocumentExit || current == null || previous == null) {
      return false;
    }

    final intersection = current.intersect(previous);
    final intersectionArea = intersection.isEmpty
        ? 0.0
        : intersection.width * intersection.height;
    final unionArea =
        current.width * current.height +
        previous.width * previous.height -
        intersectionArea;
    final iou = unionArea <= 0 ? 0.0 : intersectionArea / unionArea;
    final currentAspect = current.width / current.height;
    final previousAspect = previous.width / previous.height;
    final aspectChange = currentAspect > previousAspect
        ? currentAspect / previousAspect
        : previousAspect / currentAspect;

    if (iou < 0.58 ||
        aspectChange > 1.30 ||
        (current.center - previous.center).distance > 0.10) {
      _awaitDocumentExit = false;
      return true;
    }
    return false;
  }

  void _startPassportFrameRotation(DragStartDetails details) {
    final rect = _passportFrameRect;
    if (rect == null) return;
    const hitRadius = 38.0;
    final position = details.localPosition;
    final scale = _manualRotationFitScale(
      rect,
      _passportManualAngle,
      compactLandscape: _compactLandscapeFrame(_selectedFeature),
    );
    Offset rotatePoint(Offset point) {
      final relative = (point - rect.center) * scale;
      final cosine = math.cos(_passportManualAngle);
      final sine = math.sin(_passportManualAngle);
      return rect.center +
          Offset(
            relative.dx * cosine - relative.dy * sine,
            relative.dx * sine + relative.dy * cosine,
          );
    }

    final corners = <Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ].map(rotatePoint).toList(growable: false);
    double distanceToSegment(Offset point, Offset start, Offset end) {
      final segment = end - start;
      final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
      if (lengthSquared == 0) return (point - start).distance;
      final relative = point - start;
      final t =
          ((relative.dx * segment.dx + relative.dy * segment.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      final closest = start + segment * t;
      return (point - closest).distance;
    }

    _passportRotationDragActive = List<int>.generate(4, (i) => i).any(
      (i) =>
          distanceToSegment(position, corners[i], corners[(i + 1) % 4]) <=
          hitRadius,
    );
    if (!_passportRotationDragActive) return;
    _passportRotationStartAngle = _passportManualAngle;
    _passportPointerStartAngle = math.atan2(
      position.dy - rect.center.dy,
      position.dx - rect.center.dx,
    );
  }

  void _updatePassportFrameRotation(DragUpdateDetails details) {
    if (!_passportRotationDragActive) return;
    final rect = _passportFrameRect;
    if (rect == null) return;
    final pointerAngle = math.atan2(
      details.localPosition.dy - rect.center.dy,
      details.localPosition.dx - rect.center.dx,
    );
    var delta = pointerAngle - _passportPointerStartAngle;
    while (delta > math.pi) {
      delta -= math.pi * 2;
    }
    while (delta < -math.pi) {
      delta += math.pi * 2;
    }
    setState(() {
      _passportManualAngle = (_passportRotationStartAngle + delta).clamp(
        -math.pi / 2,
        math.pi / 2,
      );
    });
  }

  void _finishPassportFrameRotation(DragEndDetails _) {
    if (!_passportRotationDragActive) return;
    final double snapped;
    if (_passportManualAngle >= math.pi / 4) {
      snapped = math.pi / 2;
    } else if (_passportManualAngle <= -math.pi / 4) {
      snapped = -math.pi / 2;
    } else {
      snapped = 0;
    }
    if ((_passportManualAngle - snapped).abs() > 0.01) {
      HapticFeedback.mediumImpact();
    }
    setState(() {
      _passportManualAngle = snapped;
      _passportRotationDragActive = false;
    });
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
    if (!_isDocumentDetectionStreaming ||
        _isDocumentFrameBusy ||
        _isScanning ||
        !mounted) {
      return;
    }

    // Каждый 3-й кадр (~10 обработок/сек при 30 fps): анализ идёт на
    // UI-потоке, и более частая обработка давала заметный лаг превью.
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
      var passportPageChanged = false;
      if (_isRestorePhotoFeature(featureName) ||
          _isRemoveSpotsFeature(featureName) ||
          _isRemoveWatermarkFeature(featureName) ||
          _isEcoFeature(featureName)) {
        // Тот же двухступенчатый путь, что у паспорта: если замкнутый
        // контур не найден, ищем четыре стороны в зоне рамки. Важно:
        // этот поиск возвращает сам quad, поэтому UI может показать
        // детекцию и плавно подстроить рамку.
        final searchQuad = quadFound
            ? null
            : _findFramedDocumentBySearch(image, featureName);
        if (searchQuad != null) {
          _photoQuad.value = searchQuad;
          _updateAutoFrame(searchQuad, featureName);
        }
        final framedDocument = quadFound || searchQuad != null
            ? false
            : _detectDocumentContour(image, featureName: featureName);
        detected = _stabilizedDetection(
          quadFound || searchQuad != null || framedDocument,
        );
      } else if (_isDocumentSheetFeature(featureName)) {
        // Один проверенный quad управляет и состоянием детекции, и рамкой.
        // Булевую эвристику поверхности здесь не используем: она принимала
        // границу ковра/пола за документ и запускала ложный автоснимок.
        final searchQuad = quadFound
            ? null
            : _findFramedDocumentBySearch(image, featureName);
        if (searchQuad != null) {
          _photoQuad.value = searchQuad;
          _updateAutoFrame(searchQuad, featureName);
        }
        detected = _stabilizedDetection(quadFound || searchQuad != null);
      } else if (_isIdOrPassportFeature(featureName)) {
        // Паспорт/ID: два независимых сигнала через ИЛИ, оба с геометрической
        // валидацией (аспект/позиция/размер) + покадровая стабилизация:
        //  1) реальный четырёхугольник из кандидатов контурного детектора
        //     (внутри _updatePhotoQuad);
        //  2) поиск четырёх краёв документа сканированием полос в зоне рамки —
        //     работает, когда Canny не замыкает контур (край страницы
        //     сливается с линиями пола).
        // Старая эвристика фиксированных линий не используется: она давала
        // ложные срабатывания на ковре и не находила вертикальную страницу.
        final rawSearchQuad = quadFound
            ? null
            : _findFramedDocumentBySearch(image, featureName);
        List<Offset>? searchQuad = rawSearchQuad;
        if (featureName == Feat.passport && rawSearchQuad != null) {
          searchQuad = _passportDataPageFromSpread(rawSearchQuad, image);
          if (searchQuad != null &&
              !_quadLooksLikeFramedDocument(searchQuad, image, featureName)) {
            searchQuad = null;
          }
        }
        if (searchQuad != null && _isIdOrPassportFeature(featureName)) {
          _photoQuad.value = searchQuad;
          _updateAutoFrame(searchQuad, featureName);
        }
        final hasPassportCandidate = quadFound || searchQuad != null;
        final passportCandidate = quadFound ? _photoQuad.value : searchQuad;
        final passportGeometryStable =
            featureName != Feat.passport ||
            (passportCandidate != null &&
                _passportGeometryIsStable(passportCandidate));
        if (featureName == Feat.passport && !hasPassportCandidate) {
          _previousPassportFallbackBounds = null;
          _passportFallbackStableFrames = 0;
        }
        final match = hasPassportCandidate && passportGeometryStable;
        if (featureName == Feat.passport && match) {
          passportPageChanged = _unlockPassportAfterPageChange(
            _autoFrameBounds[featureName],
          );
        }
        detected = _stabilizedDetection(match);
      } else {
        detected = _detectDocumentContour(image, featureName: featureName);
      }
      if (!mounted || !_isDocumentDetectionStreaming) return;
      if (detected == _isDocumentDetected) {
        if (detected && passportPageChanged) {
          _scheduleAutoCapture();
        }
        if (!detected && _quadLostFrames >= _kQuadLost) {
          _photoQuad.value = null;
          _autoFrameBounds.remove(featureName);
        }
        return;
      }

      captureModeController.isDocumentDetected = detected;
      captureModeController.detectionWarning = null;
      if (detected) {
        _detectionAnimationController.forward(from: 0.0);
        // Не снимаем, пока ждём, что прошлую сторону уберут из кадра.
        if (!_awaitDocumentExit) {
          _scheduleAutoCapture();
        }
      } else {
        _photoQuad.value = null;
        _autoFrameBounds.remove(featureName);
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
        !_isRemoveSpotsFeature(featureName) &&
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
    final bool isPhotoFilter =
        _isRestorePhotoFeature(featureName) ||
        _isRemoveSpotsFeature(featureName) ||
        _isRemoveWatermarkFeature(featureName) ||
        _isEcoFeature(featureName);
    final int targetWidth = (isDoc || isIdPass || isPhotoFilter) ? 300 : 180;
    final int targetHeight = ((targetWidth * image.width) / image.height)
        .round()
        .clamp(160, 540);
    final gray = _samplePortraitLuma(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    // Паспортные страницы и листы документов — светлые/«пустоватые».
    // Берём ВСЕХ кандидатов и выбираем похожего на документ (а не первый
    // попавшийся): самый большой прямоугольник сцены — часто пол/ковёр.
    // Документ идёт по тому же строгому пути, что и паспорт/ID: рамочные
    // проверки + фильтр сквозных линий убирают «странные» автоснимки.
    List<Offset>? quad;
    if (isIdPass || isDoc || isPhotoFilter) {
      List<Offset>? passportFallbackQuad;
      List<Offset>? photoFallbackQuad;
      final candidates = detectPhotoQuads(
        gray,
        targetWidth,
        targetHeight,
        lowContrast: true,
      );
      if (isDoc) {
        final spread = _mergeDocumentSpreadCandidates(candidates, image);
        if (spread != null) {
          final xs = spread.map((point) => point.dx * targetWidth);
          final ys = spread.map((point) => point.dy * targetHeight);
          final left = xs.reduce(math.min).round();
          final right = xs.reduce(math.max).round();
          final top = ys.reduce(math.min).round();
          final bottom = ys.reduce(math.max).round();
          if (!_rectHasThroughEdges(
            gray,
            targetWidth,
            targetHeight,
            left,
            top,
            right,
            bottom,
          )) {
            quad = spread;
          }
        }
      }
      for (final rawCandidate in candidates) {
        if (quad != null) break;
        var candidate = rawCandidate;
        if (featureName == Feat.passport) {
          final dataPage = _passportDataPageFromSpread(
            rawCandidate,
            image,
            gray: gray,
            sampleWidth: targetWidth,
            sampleHeight: targetHeight,
          );
          if (dataPage != null) {
            candidate = dataPage;
          }
        }
        if (!_quadLooksLikeFramedDocument(candidate, image, featureName)) {
          continue;
        }
        if (featureName == Feat.passport) {
          passportFallbackQuad ??= candidate;
        }
        if (isPhotoFilter) {
          // У фото край часто соединён с рукой, рамкой снимка или фактурой
          // стола. Сохраняем геометрически правдоподобный контур до строгой
          // проверки продолжения линий и используем его после стабилизации.
          photoFallbackQuad ??= candidate;
        }
        // Bounding box кандидата: края документа должны заканчиваться на
        // углах, сквозные линии сцены (ковёр/половицы) отбрасываем.
        final xs = candidate.map((p) => p.dx * targetWidth);
        final ys = candidate.map((p) => p.dy * targetHeight);
        final bboxLeft = xs.reduce(math.min).round();
        final bboxRight = xs.reduce(math.max).round();
        final bboxTop = ys.reduce(math.min).round();
        final bboxBottom = ys.reduce(math.max).round();
        final candidateArea =
            ((bboxRight - bboxLeft) / targetWidth) *
            ((bboxBottom - bboxTop) / targetHeight);
        final hasThroughEdges = _rectHasThroughEdges(
          gray,
          targetWidth,
          targetHeight,
          bboxLeft,
          bboxTop,
          bboxRight,
          bboxBottom,
        );
        // У страницы раскрытого документа верхняя и нижняя кромки могут
        // продолжаться на соседнюю страницу. Большой контур при этом валиден;
        // небольшие полосы текста уже отсечены геометрией выше.
        if (hasThroughEdges && !(isDoc && candidateArea >= 0.28)) {
          continue;
        }
        quad = candidate;
        break;
      }
      quad ??= passportFallbackQuad ?? photoFallbackQuad;
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
    _updateAutoFrame(_photoQuad.value, featureName);
    return true;
  }

  /// If the contour covers an open passport, split it at the horizontal fold
  /// and return only the lower data page. A single passport page and a full
  /// two-page spread have almost the same outer aspect ratio, so geometry alone
  /// cannot distinguish them reliably.
  List<Offset>? _passportDataPageFromSpread(
    List<Offset> quad,
    CameraImage image, {
    List<int>? gray,
    int? sampleWidth,
    int? sampleHeight,
  }) {
    if (quad.length != 4) return null;
    final tl = quad[0];
    final tr = quad[1];
    final br = quad[2];
    final bl = quad[3];
    final width = ((tr - tl).distance + (br - bl).distance) / 2;
    final height = ((bl - tl).distance + (br - tr).distance) / 2;
    if (width < 0.45 || height < 0.34 || width * height < 0.16) {
      return null;
    }

    final physicalAspect = width * (image.height / image.width) / height;
    final foldGray =
        gray ??
        _samplePortraitLuma(
          image,
          targetWidth: 160,
          targetHeight: ((160 * image.width) / image.height).round().clamp(
            180,
            360,
          ),
        );
    final foldWidth = sampleWidth ?? 160;
    final foldHeight = sampleHeight ?? (foldGray.length ~/ foldWidth);
    // A horizontal binding is possible only when the candidate is wider than
    // a single portrait page. The fold detector itself verifies that the line
    // is continuous, so a normal text or MRZ row is not enough.
    final horizontalFoldT = physicalAspect < 1.12
        ? _passportHorizontalFoldT(quad, foldGray, foldWidth, foldHeight)
        : null;

    if (horizontalFoldT == null) {
      // Полный горизонтальный разворот: сгиб проходит через ЦЕНТР кандидата
      // (боковые полосы поиска биндинга его сознательно не покрывают).
      // Режем по сгибу и оставляем страницу с большей плотностью деталей —
      // портрет и MRZ делают страницу данных заметно «шумнее» соседней.
      if (physicalAspect >= 1.12) {
        final centerFoldT = _passportCenterFoldT(
          quad,
          foldGray,
          foldWidth,
          foldHeight,
        );
        if (centerFoldT != null) {
          final clampedT = centerFoldT.clamp(0.38, 0.62);
          final foldTop = Offset.lerp(tl, tr, clampedT)!;
          final foldBottom = Offset.lerp(bl, br, clampedT)!;
          const inset = 0.03;
          final keepRight = _passportKeepRightOfCenterFold(
            quad,
            clampedT,
            foldGray,
            foldWidth,
            foldHeight,
          );
          if (keepRight) {
            return <Offset>[
              Offset.lerp(foldTop, tr, inset)!,
              tr,
              br,
              Offset.lerp(foldBottom, br, inset)!,
            ];
          }
          return <Offset>[
            tl,
            Offset.lerp(foldTop, tl, inset)!,
            Offset.lerp(foldBottom, bl, inset)!,
            bl,
          ];
        }
      }
      final bindingSide = _passportVerticalBindingSide(
        quad,
        foldGray,
        foldWidth,
        foldHeight,
      );
      if (bindingSide != 0 && physicalAspect > 0.74) {
        const targetPortraitAspect = 0.74;
        final keepWidth = (targetPortraitAspect / physicalAspect).clamp(
          0.48,
          1.0,
        );
        if (bindingSide < 0) {
          final leftT = (1.0 - keepWidth + 0.018).clamp(0.0, 0.52);
          return <Offset>[
            Offset.lerp(tl, tr, leftT)!,
            tr,
            br,
            Offset.lerp(bl, br, leftT)!,
          ];
        }
        final rightT = (keepWidth - 0.018).clamp(0.48, 1.0);
        return <Offset>[
          tl,
          Offset.lerp(tl, tr, rightT)!,
          Offset.lerp(bl, br, rightT)!,
          bl,
        ];
      }
      // A cover or a single portrait/landscape page is already the desired
      // document when no continuous horizontal binding is present.
      const sideInset = 0.012;
      return <Offset>[
        Offset.lerp(tl, tr, sideInset)!,
        Offset.lerp(tr, tl, sideInset)!,
        Offset.lerp(br, bl, sideInset)!,
        Offset.lerp(bl, br, sideInset)!,
      ];
    }

    // Use the fold measured in this frame instead of a fixed midpoint. The
    // fallback line search frequently picks the MRZ as the bottom edge, so the
    // lower corners are reconstructed from the standard passport-page aspect
    // rather than copied from that unreliable edge.
    final foldT = horizontalFoldT.clamp(0.36, 0.64);
    const sideInset = 0.018;
    const landscapePageAspect = 1.42;
    final rawFoldLeft = Offset.lerp(tl, bl, foldT)!;
    final rawFoldRight = Offset.lerp(tr, br, foldT)!;
    // Обычно страница данных — нижняя, но паспорт держат и «вверх ногами».
    // MRZ решает: если она убедительно в ВЕРХНЕЙ половине — возвращаем
    // верхнюю страницу (она видна целиком, реконструкция углов не нужна).
    {
      final bounds = _quadBounds(quad);
      final left = (bounds.left * foldWidth).round().clamp(2, foldWidth - 3);
      final right = (bounds.right * foldWidth).round().clamp(2, foldWidth - 3);
      final top = (bounds.top * foldHeight).round().clamp(2, foldHeight - 3);
      final bottom = (bounds.bottom * foldHeight).round().clamp(
        2,
        foldHeight - 3,
      );
      final foldY = (top + (bottom - top) * foldT).round();
      final topMrz = _passportMrzBandScore(
        foldGray,
        foldWidth,
        foldHeight,
        left,
        right,
        top,
        foldY,
        verticalText: false,
      );
      final bottomMrz = _passportMrzBandScore(
        foldGray,
        foldWidth,
        foldHeight,
        left,
        right,
        foldY,
        bottom,
        verticalText: false,
      );
      if (topMrz >= 0.40 && topMrz >= bottomMrz * 1.25) {
        final topFoldInset = (rawFoldRight - rawFoldLeft) * sideInset;
        return <Offset>[
          Offset.lerp(tl, tr, sideInset)!,
          Offset.lerp(tr, tl, sideInset)!,
          rawFoldRight - topFoldInset,
          rawFoldLeft + topFoldInset,
        ];
      }
    }
    final pageFoldWidth = (rawFoldRight - rawFoldLeft).distance;
    final targetPageHeight =
        pageFoldWidth * (image.height / image.width) / landscapePageAspect;
    final leftPageVector = bl - rawFoldLeft;
    final rightPageVector = br - rawFoldRight;
    final leftScale = leftPageVector.distance <= 0.001
        ? 1.0
        : (targetPageHeight / leftPageVector.distance).clamp(0.80, 1.30);
    final rightScale = rightPageVector.distance <= 0.001
        ? 1.0
        : (targetPageHeight / rightPageVector.distance).clamp(0.80, 1.30);
    final reconstructedBottomLeft = rawFoldLeft + leftPageVector * leftScale;
    final reconstructedBottomRight =
        rawFoldRight + rightPageVector * rightScale;
    final foldInset = (rawFoldRight - rawFoldLeft) * sideInset;
    final bottomInset =
        (reconstructedBottomRight - reconstructedBottomLeft) * sideInset;
    return <Offset>[
      rawFoldLeft + foldInset,
      rawFoldRight - foldInset,
      reconstructedBottomRight - bottomInset,
      reconstructedBottomLeft + bottomInset,
    ];
  }

  double? _passportHorizontalFoldT(
    List<Offset> quad,
    List<int> gray,
    int width,
    int height,
  ) {
    final bounds = _quadBounds(quad);
    final left = (bounds.left * width).round().clamp(2, width - 3);
    final right = (bounds.right * width).round().clamp(2, width - 3);
    final top = (bounds.top * height).round().clamp(2, height - 3);
    final bottom = (bounds.bottom * height).round().clamp(2, height - 3);
    final boxWidth = right - left;
    final boxHeight = bottom - top;
    if (boxWidth < 24 || boxHeight < 24) return null;

    final x0 = left + (boxWidth * 0.08).round();
    final x1 = right - (boxWidth * 0.08).round();
    final y0 = top + (boxHeight * 0.30).round();
    final y1 = top + (boxHeight * 0.62).round();
    // The fold between two pale passport pages is often only a 4-8 luma
    // transition. A high scene-wide threshold misses it because printed text
    // and a textured floor make the global edge mean much larger.
    final gradientThreshold = math.min(
      8.0,
      math.max(4.0, _globalEdgeMean(gray, width, height) * 0.55),
    );

    var bestScore = 0.0;
    var bestY = -1;
    for (int y = y0; y <= y1; y += 2) {
      var strong = 0;
      var currentRun = 0;
      var longestRun = 0;
      var toleratedGap = 0;
      var samples = 0;
      for (int x = x0; x <= x1; x += 2) {
        final above = gray[(y - 2).clamp(0, height - 1) * width + x];
        final below = gray[(y + 2).clamp(0, height - 1) * width + x];
        if ((below - above).abs() >= gradientThreshold) {
          strong++;
          currentRun++;
          toleratedGap = 0;
          longestRun = math.max(longestRun, currentRun);
        } else if (currentRun > 0 && toleratedGap < 2) {
          // Stitching, glare and the printed header can interrupt the physical
          // fold for a few pixels; keep the same long component through them.
          currentRun++;
          toleratedGap++;
        } else {
          currentRun = 0;
          toleratedGap = 0;
        }
        samples++;
      }
      if (samples > 0) {
        final coverage = strong / samples;
        final runRatio = longestRun / samples;
        if (coverage >= 0.30 && runRatio >= 0.22) {
          final score = coverage * 0.65 + runRatio * 0.35;
          if (score > bestScore) {
            bestScore = score;
            bestY = y;
          }
        }
      }
    }
    if (bestY < 0) return null;
    return ((bestY - top) / boxHeight).clamp(0.0, 1.0);
  }

  /// Непрерывный вертикальный сгиб в ЦЕНТРАЛЬНОЙ полосе кандидата
  /// (40–60% ширины) — признак полного горизонтального разворота. Порог
  /// низкий, как у горизонтального сгиба: перепад между двумя бледными
  /// страницами составляет всего 4–8 люмы. Возвращает позицию сгиба в
  /// долях ширины кандидата или null.
  double? _passportCenterFoldT(
    List<Offset> quad,
    List<int> gray,
    int width,
    int height,
  ) {
    final bounds = _quadBounds(quad);
    final left = (bounds.left * width).round().clamp(2, width - 3);
    final right = (bounds.right * width).round().clamp(2, width - 3);
    final top = (bounds.top * height).round().clamp(2, height - 3);
    final bottom = (bounds.bottom * height).round().clamp(2, height - 3);
    final boxWidth = right - left;
    final boxHeight = bottom - top;
    if (boxWidth < 24 || boxHeight < 24) return null;

    final y0 = top + (boxHeight * 0.08).round();
    final y1 = bottom - (boxHeight * 0.08).round();
    final x0 = left + (boxWidth * 0.40).round();
    final x1 = left + (boxWidth * 0.60).round();
    final gradientThreshold = math.min(
      8.0,
      math.max(4.0, _globalEdgeMean(gray, width, height) * 0.55),
    );

    var bestScore = 0.0;
    var bestX = -1;
    for (int x = x0; x <= x1; x += 2) {
      var strong = 0;
      var currentRun = 0;
      var longestRun = 0;
      var toleratedGap = 0;
      var samples = 0;
      for (int y = y0; y <= y1; y += 2) {
        final lumaLeft = gray[y * width + (x - 2).clamp(0, width - 1)];
        final lumaRight = gray[y * width + (x + 2).clamp(0, width - 1)];
        if ((lumaRight - lumaLeft).abs() >= gradientThreshold) {
          strong++;
          currentRun++;
          toleratedGap = 0;
          longestRun = math.max(longestRun, currentRun);
        } else if (currentRun > 0 && toleratedGap < 2) {
          // Прошивка и блики прерывают физический сгиб на пару пикселей —
          // считаем это тем же длинным компонентом.
          currentRun++;
          toleratedGap++;
        } else {
          currentRun = 0;
          toleratedGap = 0;
        }
        samples++;
      }
      if (samples > 0) {
        final coverage = strong / samples;
        final runRatio = longestRun / samples;
        if (coverage >= 0.30 && runRatio >= 0.22) {
          final score = coverage * 0.65 + runRatio * 0.35;
          if (score > bestScore) {
            bestScore = score;
            bestX = x;
          }
        }
      }
    }
    if (bestX < 0) return null;

    // Настоящий сгиб — «жёлоб»: линия темнее ОБЕИХ сторон. Ступенька
    // (граница тени или освещения) этот профиль не проходит — защита от
    // ложной резки одиночной страницы по тени.
    var valley = 0;
    var valleySamples = 0;
    for (int y = y0; y <= y1; y += 2) {
      final center = gray[y * width + bestX];
      final leftSide = gray[y * width + (bestX - 6).clamp(0, width - 1)];
      final rightSide = gray[y * width + (bestX + 6).clamp(0, width - 1)];
      if (center + 3 <= math.min(leftSide, rightSide)) valley++;
      valleySamples++;
    }
    if (valleySamples == 0 || valley / valleySamples < 0.30) return null;

    return ((bestX - left) / boxWidth).clamp(0.0, 1.0);
  }

  /// Скор MRZ-полосы в прямоугольнике: строки OCR-B дают плотную
  /// равномерную полосу сильных перепадов почти на всю длину строки.
  /// [verticalText] — текст повёрнут на 90° (паспорт лежит боком): строки
  /// MRZ идут вертикально, перепады считаются вдоль колонок.
  double _passportMrzBandScore(
    List<int> gray,
    int width,
    int height,
    int x0,
    int x1,
    int y0,
    int y1, {
    required bool verticalText,
  }) {
    final xa = (x0 + (x1 - x0) * 0.06).round().clamp(2, width - 3);
    final xb = (x1 - (x1 - x0) * 0.06).round().clamp(2, width - 3);
    final ya = (y0 + (y1 - y0) * 0.06).round().clamp(2, height - 3);
    final yb = (y1 - (y1 - y0) * 0.06).round().clamp(2, height - 3);
    if (xb - xa < 16 || yb - ya < 16) return 0;
    const threshold = 16;

    double lineCoverage(int linePos) {
      var strong = 0;
      var samples = 0;
      if (verticalText) {
        // Линия — колонка x=linePos, перепады вдоль Y.
        for (int y = ya; y <= yb; y += 2) {
          final a = gray[(y - 2).clamp(0, height - 1) * width + linePos];
          final b = gray[(y + 2).clamp(0, height - 1) * width + linePos];
          if ((b - a).abs() >= threshold) strong++;
          samples++;
        }
      } else {
        // Линия — строка y=linePos, перепады вдоль X.
        for (int x = xa; x <= xb; x += 2) {
          final a = gray[linePos * width + (x - 2).clamp(0, width - 1)];
          final b = gray[linePos * width + (x + 2).clamp(0, width - 1)];
          if ((b - a).abs() >= threshold) strong++;
          samples++;
        }
      }
      return samples == 0 ? 0 : strong / samples;
    }

    final from = verticalText ? xa : ya;
    final to = verticalText ? xb : yb;
    var best = 0.0;
    for (int p = from; p + 4 <= to; p += 2) {
      final coverage =
          (lineCoverage(p) + lineCoverage(p + 2) + lineCoverage(p + 4)) / 3;
      if (coverage > best) best = coverage;
    }
    return best;
  }

  /// Какую половину горизонтального разворота оставить. Сначала — надёжный
  /// признак: MRZ есть ТОЛЬКО на странице данных (при боковой укладке её
  /// строки вертикальны). Если MRZ не убедительна ни с одной стороны —
  /// фолбэк на сравнение плотности деталей.
  bool _passportKeepRightOfCenterFold(
    List<Offset> quad,
    double foldT,
    List<int> gray,
    int width,
    int height,
  ) {
    final bounds = _quadBounds(quad);
    final left = (bounds.left * width).round().clamp(2, width - 3);
    final right = (bounds.right * width).round().clamp(2, width - 3);
    final top = (bounds.top * height).round().clamp(2, height - 3);
    final bottom = (bounds.bottom * height).round().clamp(2, height - 3);
    final foldX = (left + (right - left) * foldT).round();

    final leftMrz = _passportMrzBandScore(
      gray,
      width,
      height,
      left,
      foldX,
      top,
      bottom,
      verticalText: true,
    );
    final rightMrz = _passportMrzBandScore(
      gray,
      width,
      height,
      foldX,
      right,
      top,
      bottom,
      verticalText: true,
    );
    const mrzMin = 0.40;
    if (rightMrz >= mrzMin && rightMrz >= leftMrz * 1.25) return true;
    if (leftMrz >= mrzMin && leftMrz >= rightMrz * 1.25) return false;

    return _passportRightHalfDenser(quad, foldT, gray, width, height);
  }

  /// true — правая (относительно сгиба) половина кандидата содержит больше
  /// мелких деталей. Портрет, текстовые поля и MRZ делают страницу данных
  /// заметно «шумнее» соседней визовой страницы.
  bool _passportRightHalfDenser(
    List<Offset> quad,
    double foldT,
    List<int> gray,
    int width,
    int height,
  ) {
    final bounds = _quadBounds(quad);
    final left = (bounds.left * width).round().clamp(2, width - 3);
    final right = (bounds.right * width).round().clamp(2, width - 3);
    final top = (bounds.top * height).round().clamp(2, height - 3);
    final bottom = (bounds.bottom * height).round().clamp(2, height - 3);
    final foldX = (left + (right - left) * foldT).round();

    double density(int x0, int x1) {
      final xa = (x0 + (x1 - x0) * 0.08).round();
      final xb = (x1 - (x1 - x0) * 0.08).round();
      final ya = (top + (bottom - top) * 0.10).round();
      final yb = (bottom - (bottom - top) * 0.10).round();
      if (xb - xa < 8 || yb - ya < 8) return 0;
      var sum = 0.0;
      var count = 0;
      for (int y = ya; y <= yb; y += 3) {
        for (int x = xa; x <= xb; x += 3) {
          final horizontal =
              (gray[y * width + (x + 2).clamp(0, width - 1)] -
                      gray[y * width + (x - 2).clamp(0, width - 1)])
                  .abs();
          final vertical =
              (gray[(y + 2).clamp(0, height - 1) * width + x] -
                      gray[(y - 2).clamp(0, height - 1) * width + x])
                  .abs();
          sum += horizontal + vertical;
          count++;
        }
      }
      return count == 0 ? 0 : sum / count;
    }

    return density(foldX, right) >= density(left, foldX);
  }

  /// Returns the side of an internal vertical passport binding: -1 for the
  /// left side, 1 for the right side and 0 when the candidate is already a
  /// standalone page or a cover. The search deliberately ignores the outer
  /// 8% of the quad so a normal page edge is not mistaken for a binding.
  int _passportVerticalBindingSide(
    List<Offset> quad,
    List<int> gray,
    int width,
    int height,
  ) {
    final bounds = _quadBounds(quad);
    final left = (bounds.left * width).round().clamp(2, width - 3);
    final right = (bounds.right * width).round().clamp(2, width - 3);
    final top = (bounds.top * height).round().clamp(2, height - 3);
    final bottom = (bounds.bottom * height).round().clamp(2, height - 3);
    final boxWidth = right - left;
    final boxHeight = bottom - top;
    if (boxWidth < 24 || boxHeight < 32) return 0;

    final y0 = top + (boxHeight * 0.08).round();
    final y1 = bottom - (boxHeight * 0.08).round();
    final gradientThreshold = math.max(
      12.0,
      _globalEdgeMean(gray, width, height) * 1.45,
    );

    ({double coverage, double runRatio, double score}) bestInBand(
      double fromFraction,
      double toFraction,
    ) {
      var bestCoverage = 0.0;
      var bestRunRatio = 0.0;
      var bestScore = 0.0;
      final x0 = left + (boxWidth * fromFraction).round();
      final x1 = left + (boxWidth * toFraction).round();
      for (int x = x0; x <= x1; x += 2) {
        var strong = 0;
        var currentRun = 0;
        var longestRun = 0;
        var samples = 0;
        for (int y = y0; y <= y1; y += 2) {
          final lumaLeft = gray[y * width + (x - 2).clamp(0, width - 1)];
          final lumaRight = gray[y * width + (x + 2).clamp(0, width - 1)];
          if ((lumaRight - lumaLeft).abs() >= gradientThreshold) {
            strong++;
            currentRun++;
            longestRun = math.max(longestRun, currentRun);
          } else {
            currentRun = 0;
          }
          samples++;
        }
        if (samples == 0) continue;
        final coverage = strong / samples;
        final runRatio = longestRun / samples;
        // Coverage rejects short text strokes; the uninterrupted component
        // gives extra weight to the physical seam or stitched binding.
        final score = coverage * 0.65 + runRatio * 0.35;
        if (score > bestScore) {
          bestCoverage = coverage;
          bestRunRatio = runRatio;
          bestScore = score;
        }
      }
      return (coverage: bestCoverage, runRatio: bestRunRatio, score: bestScore);
    }

    final leftBinding = bestInBand(0.08, 0.40);
    final rightBinding = bestInBand(0.60, 0.92);

    bool isBinding(({double coverage, double runRatio, double score}) value) {
      return value.coverage >= 0.30 && value.runRatio >= 0.18;
    }

    final hasLeftBinding = isBinding(leftBinding);
    final hasRightBinding = isBinding(rightBinding);
    if (!hasLeftBinding && !hasRightBinding) return 0;
    if (hasLeftBinding && !hasRightBinding) return -1;
    if (hasRightBinding && !hasLeftBinding) return 1;

    // Text or a portrait can occasionally create a candidate on both sides;
    // only choose a direction when one side is materially more continuous.
    if (leftBinding.score > rightBinding.score * 1.12) return -1;
    if (rightBinding.score > leftBinding.score * 1.12) return 1;
    return 0;
  }

  /// Объединяет две соседние страницы раскрытого документа в один внешний
  /// четырехугольник. Контурный детектор часто видит сгиб как границу и
  /// возвращает левую и правую страницы по отдельности.
  List<Offset>? _mergeDocumentSpreadCandidates(
    List<List<Offset>> candidates,
    CameraImage image,
  ) {
    if (candidates.length < 2) return null;

    Rect boundsOf(List<Offset> quad) {
      final xs = quad.map((point) => point.dx);
      final ys = quad.map((point) => point.dy);
      return Rect.fromLTRB(
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      );
    }

    final frameWOverH = image.height / image.width;

    // Горизонтальный разворот: страницы бок о бок (сгиб вертикальный).
    List<Offset>? tryMergeHorizontal(
      List<Offset> first,
      Rect firstBounds,
      List<Offset> second,
      Rect secondBounds,
    ) {
      final left = firstBounds.center.dx <= secondBounds.center.dx
          ? first
          : second;
      final right = identical(left, first) ? second : first;
      final leftBounds = identical(left, first) ? firstBounds : secondBounds;
      final rightBounds = identical(left, first) ? secondBounds : firstBounds;

      final minHeight = math.min(leftBounds.height, rightBounds.height);
      final maxHeight = math.max(leftBounds.height, rightBounds.height);
      if (maxHeight / minHeight > 1.65) return null;

      final verticalOverlap = math.max(
        0.0,
        math.min(leftBounds.bottom, rightBounds.bottom) -
            math.max(leftBounds.top, rightBounds.top),
      );
      if (verticalOverlap / minHeight < 0.72) return null;

      // Страницы могут слегка перекрываться у сгиба, но одна не должна
      // находиться внутри другой (текстовые блоки и фотографии отсекаются).
      final gap = rightBounds.left - leftBounds.right;
      final minWidth = math.min(leftBounds.width, rightBounds.width);
      if (gap < -minWidth * 0.18 || gap > minWidth * 0.42) return null;

      final merged = <Offset>[left[0], right[1], right[2], left[3]];
      final mergedBounds = boundsOf(merged);
      if (mergedBounds.width < 0.58 || mergedBounds.width > 0.98) return null;
      if (mergedBounds.height < 0.20 || mergedBounds.height > 0.62) {
        return null;
      }

      final physicalAspect =
          (mergedBounds.width * frameWOverH) / mergedBounds.height;
      if (physicalAspect < 0.90 || physicalAspect > 2.35) return null;
      return merged;
    }

    // Вертикальный разворот: паспорт лежит боком, страницы одна над другой
    // (сгиб горизонтальный) — зеркальные условия по осям.
    List<Offset>? tryMergeVertical(
      List<Offset> first,
      Rect firstBounds,
      List<Offset> second,
      Rect secondBounds,
    ) {
      final top = firstBounds.center.dy <= secondBounds.center.dy
          ? first
          : second;
      final bottom = identical(top, first) ? second : first;
      final topBounds = identical(top, first) ? firstBounds : secondBounds;
      final bottomBounds = identical(top, first) ? secondBounds : firstBounds;

      final minWidth = math.min(topBounds.width, bottomBounds.width);
      final maxWidth = math.max(topBounds.width, bottomBounds.width);
      if (maxWidth / minWidth > 1.65) return null;

      final horizontalOverlap = math.max(
        0.0,
        math.min(topBounds.right, bottomBounds.right) -
            math.max(topBounds.left, bottomBounds.left),
      );
      if (horizontalOverlap / minWidth < 0.72) return null;

      final gap = bottomBounds.top - topBounds.bottom;
      final minHeight = math.min(topBounds.height, bottomBounds.height);
      if (gap < -minHeight * 0.18 || gap > minHeight * 0.42) return null;

      final merged = <Offset>[top[0], top[1], bottom[2], bottom[3]];
      final mergedBounds = boundsOf(merged);
      if (mergedBounds.width < 0.25 || mergedBounds.width > 0.92) return null;
      if (mergedBounds.height < 0.28 || mergedBounds.height > 0.66) {
        return null;
      }

      final physicalAspect =
          (mergedBounds.width * frameWOverH) / mergedBounds.height;
      if (physicalAspect < 0.40 || physicalAspect > 1.15) return null;
      return merged;
    }

    List<Offset>? best;
    double bestArea = 0;
    final limit = math.min(candidates.length, 8);
    for (var i = 0; i < limit; i++) {
      final first = candidates[i];
      if (first.length != 4) continue;
      final firstBounds = boundsOf(first);
      if (firstBounds.width < 0.16 || firstBounds.height < 0.16) continue;

      for (var j = i + 1; j < limit; j++) {
        final second = candidates[j];
        if (second.length != 4) continue;
        final secondBounds = boundsOf(second);
        if (secondBounds.width < 0.16 || secondBounds.height < 0.16) continue;

        final merged =
            tryMergeHorizontal(first, firstBounds, second, secondBounds) ??
            tryMergeVertical(first, firstBounds, second, secondBounds);
        if (merged == null) continue;
        if (!_quadLooksLikeFramedDocument(merged, image, Feat.document)) {
          continue;
        }

        final mergedBounds = boundsOf(merged);
        final area = mergedBounds.width * mergedBounds.height;
        if (area > bestArea) {
          bestArea = area;
          best = merged;
        }
      }
    }
    return best;
  }

  /// true, если какая-то сторона прямоугольника — «сквозная» линия сцены:
  /// граница ковра через весь кадр, стык половиц во всю ширину и т.п. —
  /// линия продолжается с сопоставимой силой ЗА пределами прямоугольника.
  /// У настоящего документа края заканчиваются на его углах, поэтому
  /// продолжения слабые. Главный фильтр ложных срабатываний на полу/ковре.
  bool _rectHasThroughEdges(
    List<int> gray,
    int w,
    int h,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    final rectH = bottom - top;
    final rectW = right - left;
    if (rectH < 12 || rectW < 12) return true;
    final extV = (rectH * 0.45).round();
    final extH = (rectW * 0.45).round();
    // Базовый уровень градиентного шума сцены: на фактурном ковре даже
    // пустой сегмент даёт заметный line-score. Продолжение засчитываем
    // только если оно САМО является сильной линией, а не шумом фона —
    // иначе настоящий документ на ковре бракуется из-за текстуры вокруг.
    final double globalEdge = _globalEdgeMean(gray, w, h);
    final double lineFloor = math.max(globalEdge * 1.55, 10.0);

    double vScore(int x, int y0, int y1) =>
        (y1 - y0 < 8) ? 0 : _verticalLineScore(gray, w, h, x, y0, y1);
    double hScore(int y, int x0, int x1) =>
        (x1 - x0 < 8) ? 0 : _horizontalLineScore(gray, w, h, y, x0, x1);

    bool through(double edgeScore, double contA, double contB) {
      if (edgeScore <= 0) return false;
      final cont = math.max(contA, contB);
      if (cont < lineFloor) return false; // шум фона, не линия
      return cont > edgeScore * 0.75;
    }

    var throughEdgeCount = 0;
    // Вертикальные края: есть ли продолжение выше top / ниже bottom.
    for (final x in [left, right]) {
      if (x < 3 || x > w - 4) continue;
      final edge = vScore(x, top + 2, bottom - 2);
      final above = vScore(x, math.max(3, top - extV), top - 3);
      final below = vScore(x, bottom + 3, math.min(h - 4, bottom + extV));
      if (through(edge, above, below)) throughEdgeCount++;
    }
    // Горизонтальные края: есть ли продолжение левее left / правее right.
    for (final y in [top, bottom]) {
      if (y < 3 || y > h - 4) continue;
      final edge = hScore(y, left + 2, right - 2);
      final contLeft = hScore(y, math.max(3, left - extH), left - 3);
      final contRight = hScore(y, right + 3, math.min(w - 4, right + extH));
      if (through(edge, contLeft, contRight)) throughEdgeCount++;
    }
    // Одна сторона документа может соприкасаться с рукой, сгибом или краем
    // стола. Две продолжающиеся стороны уже характерны для линий сцены.
    return throughEdgeCount >= 2;
  }

  /// Поиск документа в зоне рамки сканированием краёв: для каждой из четырёх
  /// сторон ищем ЛУЧШУЮ прямую линию градиента в полосе поиска (а не по
  /// фиксированным позициям, как старая эвристика — она требовала документ
  /// строго по периметру рамки). Затем валидируем прямоугольник геометрически.
  /// Работает, когда контурный детектор не замыкает четырёхугольник (края
  /// страницы сливаются с линиями пола).
  List<Offset>? _findFramedDocumentBySearch(
    CameraImage image,
    String featureName,
  ) {
    final int targetWidth = featureName == Feat.passport ? 180 : 120;
    final int targetHeight = ((targetWidth * image.width) / image.height)
        .round()
        .clamp(150, featureName == Feat.passport ? 420 : 280);
    final gray = _samplePortraitLuma(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final globalEdge = _globalEdgeMean(gray, targetWidth, targetHeight);
    if (globalEdge <= 0.4) return null;

    // Рамки паспорта и ID-карты сидят одинаково (verticalAlignment -0.25),
    // паспортная чуть выше из-за большей высоты (aspect 1.42 против 1.586).
    final bool isPassport = featureName == Feat.passport;
    final bool isPhotoFilter =
        _isRestorePhotoFeature(featureName) ||
        _isRemoveSpotsFeature(featureName) ||
        _isRemoveWatermarkFeature(featureName) ||
        _isEcoFeature(featureName);
    final bool isDocumentSheet = _isDocumentSheetFeature(featureName);
    final double zoneTopF = isPassport ? 0.08 : 0.16;
    final double zoneBottomF = isPassport ? 0.80 : 0.66;
    final int zoneTop = (zoneTopF * targetHeight).round();
    final int zoneBottom = (zoneBottomF * targetHeight).round();
    final int zoneH = zoneBottom - zoneTop;
    if (zoneH < 20) return null;

    (int, double) bestHorizontal(int from, int to, int x0, int x1) {
      int bestY = -1;
      double bestScore = -1;
      for (int y = from; y <= to; y += 2) {
        if (y < 3 || y > targetHeight - 4) continue;
        final s = _horizontalLineScore(
          gray,
          targetWidth,
          targetHeight,
          y,
          x0,
          x1,
        );
        if (s > bestScore) {
          bestScore = s;
          bestY = y;
        }
      }
      return (bestY, bestScore);
    }

    (int, double) bestVertical(int from, int to, int y0, int y1) {
      int bestX = -1;
      double bestScore = -1;
      for (int x = from; x <= to; x += 2) {
        if (x < 3 || x > targetWidth - 4) continue;
        final s = _verticalLineScore(
          gray,
          targetWidth,
          targetHeight,
          x,
          y0,
          y1,
        );
        if (s > bestScore) {
          bestScore = s;
          bestX = x;
        }
      }
      return (bestX, bestScore);
    }

    // Верхний край — в верхней половине зоны, нижний — в нижней.
    final midX0 = (targetWidth * 0.22).round();
    final midX1 = (targetWidth * 0.78).round();
    final (topY, topScore) = bestHorizontal(
      zoneTop - (zoneH * 0.15).round(),
      zoneTop + (zoneH * 0.45).round(),
      midX0,
      midX1,
    );
    final (bottomY, bottomScore) = bestHorizontal(
      zoneBottom - (zoneH * 0.45).round(),
      zoneBottom + (zoneH * 0.15).round(),
      midX0,
      midX1,
    );
    if (topY < 0 || bottomY < 0 || bottomY - topY < zoneH * 0.25) return null;

    // Боковые края — между найденными верхом и низом; полосы поиска широкие,
    // чтобы находить и узкую вертикальную страницу, и разворот во всю рамку.
    final (leftX, leftScore) = bestVertical(
      (targetWidth * 0.04).round(),
      (targetWidth * 0.48).round(),
      topY + 2,
      bottomY - 2,
    );
    final (rightX, rightScore) = bestVertical(
      (targetWidth * 0.52).round(),
      (targetWidth * 0.96).round(),
      topY + 2,
      bottomY - 2,
    );
    if (leftX < 0 || rightX < 0) return null;

    // Все четыре края должны быть выраженными и заметно сильнее среднего
    // градиента сцены (на фактурном ковре globalEdge высокий — порог растёт).
    final double minScore = isPassport
        ? math.max(globalEdge * 1.10, 6.0)
        : (isPhotoFilter || isDocumentSheet)
        ? math.max(globalEdge * 1.25, 8.0)
        : math.max(globalEdge * 1.7, 11.0);
    final edgeScores = [topScore, bottomScore, leftScore, rightScore];
    final hasStrongHorizontal = topScore >= minScore || bottomScore >= minScore;
    final hasStrongVertical = leftScore >= minScore || rightScore >= minScore;
    final strongEdgeCount = edgeScores
        .where((score) => score >= minScore)
        .length;
    // Закрытый документ должен дать четыре стороны; у открытой страницы или
    // сгиба допускается одна потерянная сторона, но не две.
    final requiredEdges = isPassport ? 2 : (isDocumentSheet ? 3 : 4);
    if (strongEdgeCount < requiredEdges) {
      return null;
    }

    // Геометрия: размеры и аспект документа (px квадратные — сэмплер
    // сохраняет пропорции кадра), центр в зоне рамки.
    final resolvedLeftX = leftX;
    final resolvedRightX = rightX;
    final resolvedTopY = topY;
    final resolvedBottomY = bottomY;

    final double w = (resolvedRightX - resolvedLeftX).toDouble();
    final double h = (resolvedBottomY - resolvedTopY).toDouble();
    if (w < targetWidth * 0.24 || h < targetHeight * 0.12) return null;
    if (isDocumentSheet &&
        (w < targetWidth * 0.56 ||
            h < targetHeight * 0.28 ||
            w * h < targetWidth * targetHeight * 0.20)) {
      return null;
    }
    final double aspect = w / h;
    if (aspect < 0.42 || aspect > 2.6) return null;
    if (isPassport && strongEdgeCount == 2) {
      final candidateArea = w * h / (targetWidth * targetHeight);
      final averageEdgeScore =
          edgeScores.fold<double>(0, (sum, score) => sum + score) /
          edgeScores.length;
      // The two-edge relaxation is only for a large standalone page whose
      // low-contrast outer edges blend into the neighbouring paper. Requiring
      // adjacent directions prevents two text/MRZ rows from triggering the
      // horizontal fallback early.
      if (!hasStrongHorizontal ||
          !hasStrongVertical ||
          candidateArea < 0.18 ||
          aspect < 0.55 ||
          aspect > 1.85 ||
          averageEdgeScore < minScore * 0.82) {
        return null;
      }
    }
    final double centerY = (resolvedTopY + resolvedBottomY) / 2 / targetHeight;
    if (centerY < zoneTopF || centerY > zoneBottomF) return null;

    final candidateQuad = <Offset>[
      Offset(resolvedLeftX / targetWidth, resolvedTopY / targetHeight),
      Offset(resolvedRightX / targetWidth, resolvedTopY / targetHeight),
      Offset(resolvedRightX / targetWidth, resolvedBottomY / targetHeight),
      Offset(resolvedLeftX / targetWidth, resolvedBottomY / targetHeight),
    ];
    // Края документа должны заканчиваться на углах: сквозные линии сцены
    // (граница ковра, стык половиц) — не документ.
    if (_rectHasThroughEdges(
      gray,
      targetWidth,
      targetHeight,
      resolvedLeftX,
      resolvedTopY,
      resolvedRightX,
      resolvedBottomY,
    )) {
      return null;
    }

    // Обновляем видимую рамку только после всех проверок. Раньше даже
    // отклонённый кандидат успевал стянуть её к внутреннему блоку текста.
    return candidateQuad;
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
    final widthNorm = (topLen + bottomLen) / 2;
    final heightNorm = (leftLen + rightLen) / 2;
    if (heightNorm < 0.08 || heightNorm > (isPassport ? 0.72 : 0.58)) {
      return false;
    }
    if (isPassport) {
      // The portrait, text fields and MRZ often form a very clean rectangle
      // inside the data page. It must not drive the frame or auto-capture: a
      // real passport page occupies a materially larger part of the preview.
      // Use normalized sensor area so a page remains valid after a 90° turn.
      final normalizedArea = widthNorm * heightNorm;
      if (normalizedArea < 0.14) return false;
    }
    if (_isDocumentSheetFeature(featureName)) {
      // Полосы текста, MRZ и крупные внутренние блоки часто образуют хороший
      // прямоугольник, но они заметно ниже и меньше самой страницы.
      if (widthNorm < 0.56 || heightNorm < 0.28) return false;
      if (widthNorm * heightNorm < 0.20) return false;
    }

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
    final captureDelay = _selectedFeature == Feat.passport
        ? const Duration(milliseconds: 850)
        : const Duration(milliseconds: 550);
    _autoCaptureTimer = Timer(captureDelay, () {
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
    final hasConfirmedPassportFrame =
        feature != Feat.passport || _autoFrameBounds[Feat.passport] != null;
    if (!mounted ||
        _isScanning ||
        !_isDocumentDetected ||
        !hasConfirmedPassportFrame ||
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
    if (_selectedFeature != Feat.idCard || _currentSide != 'Лицевая') {
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
    final minVertical = globalEdge * (isDocumentSheet ? 1.10 : 1.45);
    final minHorizontal = globalEdge * (isDocumentSheet ? 1.08 : 1.35);
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
        ? strongLineCount >= 2 && averageFrameScore > globalEdge * 1.12
        : strongLineCount >= 3 && averageFrameScore > globalEdge * 1.45;
    final areaRatio =
        ((right - left) * (bottom - top)) / (targetWidth * targetHeight);
    final hasPlainDocumentSurface =
        (innerVariance < 1500 && innerMean > 118) ||
        (innerMean > 92 && innerMean - outerMean > 16);
    final hasDetailedDocumentSurface = innerMean > 122 && innerVariance < 5200;
    final hasDocumentSurface = isDocumentSheet
        ? innerMean > 32 && innerVariance < 9000
        : hasPlainDocumentSurface || hasDetailedDocumentSurface;

    // Карта всегда заметно ЯРЧЕ окружения (карта светлая, рука/стол/ковёр
    // темнее). Без этого условия детектор ложно срабатывал на однородном
    // ярком фоне и снимал «документ», когда карты в кадре нет.
    final hasContrast = isDocumentSheet
        ? (innerMean - outerMean).abs() > 7
        : innerMean - outerMean > 14;

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
        // Рамка листа (widthFactor 0.80, alignment -0.35):
        // верх ~0.15 H, низ ~0.69 H.
        return const [
          _DocumentFrameSpec(left: 0.10, right: 0.90, top: 0.15, bottom: 0.69),
          _DocumentFrameSpec(left: 0.07, right: 0.93, top: 0.10, bottom: 0.75),
          _DocumentFrameSpec(left: 0.13, right: 0.87, top: 0.20, bottom: 0.63),
        ];
      case Feat.restorePhoto:
      case Feat.removeSpots:
      case Feat.removeWatermark:
      case Feat.eco:
        // Высокая рамка фото-фильтров (aspect 0.75, alignment -0.30).
        return const [
          _DocumentFrameSpec(left: 0.11, right: 0.89, top: 0.18, bottom: 0.66),
          _DocumentFrameSpec(left: 0.07, right: 0.93, top: 0.13, bottom: 0.72),
          _DocumentFrameSpec(left: 0.15, right: 0.85, top: 0.22, bottom: 0.62),
        ];
      case Feat.passport:
      default:
        // Рамка паспорта (verticalAlignment -0.25, как у ID-карты):
        // верх ~0.26–0.28 H, низ ~0.54–0.57 H.
        return const [
          _DocumentFrameSpec(left: 0.08, right: 0.92, top: 0.26, bottom: 0.56),
          _DocumentFrameSpec(left: 0.06, right: 0.94, top: 0.23, bottom: 0.60),
          _DocumentFrameSpec(left: 0.10, right: 0.90, top: 0.29, bottom: 0.53),
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
    _lastPassportCaptureBounds = null;
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

    final previewFiles = List<XFile>.from(_multiPageBatch);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MultiPageDocumentPreviewScreen(
          imageFiles: previewFiles,
          onRetakeAll: () {
            Navigator.pop(context);
            setState(_resetMultiPageState);
            _startDocumentDetectionStream();
          },
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
    if (croppedFile.path != file.path) return XFile(croppedFile.path);
    // Сканер не нашёл страницу на снимке (и сегментация, и поиск по краям
    // промахнулись). Последний рубеж — кроп по live-рамке, зафиксированной
    // в момент нажатия затвора: лучше кадр по рамке, чем весь фон целиком.
    final bounds = _captureFrameBounds ?? _autoFrameBounds[Feat.passport];
    if (bounds == null) return file;
    final fallback = await PassportScanner.cropByNormalizedRect(
      File(file.path),
      bounds,
    );
    return XFile(fallback.path);
  }

  Future<XFile> _autoCropDocumentXFile(XFile file) async {
    final croppedFile = await DocumentScanner.autoCrop(File(file.path));
    return XFile(croppedFile.path);
  }

  /// Паспорт: свободное сканирование в буфер без выбора количества страниц.
  /// Пользователь снимает до [_passportMaxPages] страниц, затем жмёт галочку.
  static const int _passportMaxPages = 7;

  sb.DocumentScanningFlow _scanbotPassportConfiguration(int pageLimit) {
    final configuration = sb.DocumentScanningFlow();

    configuration.palette
      ..sbColorPrimary = sb.ScanbotColor('#16C784')
      ..sbColorPositive = sb.ScanbotColor('#16C784')
      ..sbColorSecondary = sb.ScanbotColor('#DDF8EC')
      ..sbColorOnSecondary = sb.ScanbotColor('#087A50');

    configuration.outputSettings
      ..pagesScanLimit = pageLimit
      ..documentImageSizeLimit = 0;

    final camera = configuration.screens.camera;
    camera
      ..autoRotateImages = true
      ..openReviewAfterEachScan = false;
    camera.cameraConfiguration
      ..autoSnappingEnabled = true
      // Даём контуру стабилизироваться перед автоматическим снимком.
      ..autoSnappingSensitivity = 0.45
      ..autoSnappingDelay = 700
      ..touchToFocusEnabled = true
      ..captureQualityPrioritization =
          sb.CapturePhotoQualityPrioritization.QUALITY
      ..fpsLimit = 20;
    camera.scannerParameters
      // Для паспорта важнее принять страницу на комфортном расстоянии,
      // чем заставлять пользователя доводить её до краёв экрана.
      ..acceptedSizeScore = 55
      ..acceptedAngleScore = 65
      // Паспортные страницы встречаются в обеих ориентациях и пропорциях.
      ..acceptedAspectRatioScore = 0
      ..ignoreOrientationMismatch = true;
    camera.acknowledgement.acknowledgementMode = sb.AcknowledgementMode.ALWAYS;
    camera.introduction.showAutomatically = false;
    configuration.screens.review
      ..enabled = true
      ..showLastPageWhenAdding = true;

    final text = configuration.localization;
    text
      ..cameraTopBarTitle = 'Паспорт'
      ..cameraTopGuidance = 'Сканируйте страницы паспорта по очереди'
      ..cameraUserGuidanceStart = 'Наведите камеру на страницу паспорта'
      ..cameraUserGuidanceNoDocumentFound = 'Страница не найдена'
      ..cameraUserGuidanceBadAspectRatio = 'Покажите страницу целиком'
      ..cameraUserGuidanceOrientationMismatch =
          'Поверните устройство к странице'
      ..cameraUserGuidanceBadAngles = 'Держите камеру параллельно странице'
      ..cameraUserGuidanceTooNoisy = 'Используйте более однородный фон'
      ..cameraUserGuidanceTextHintOffCenter = 'Поместите страницу по центру'
      ..cameraUserGuidanceTooSmall = 'Поднесите камеру немного ближе'
      ..cameraUserGuidanceTooDark = 'Добавьте освещение'
      ..cameraUserGuidanceReadyToCapture = 'Не двигайте устройство'
      ..cameraUserGuidanceReadyToCaptureManual = 'Страница готова к снимку'
      ..cameraAutoSnapButtonTitle = 'Авто'
      ..cameraManualSnapButtonTitle = 'Ручн.'
      ..cameraPreviewButtonTitle = '%d стр.'
      ..cameraTopBarCancelButtonTitle = 'Отмена'
      ..cameraProgressOverlayTitle = 'Обработка…'
      ..acknowledgementRetakeButtonTitle = 'Переснять'
      ..acknowledgementAcceptButtonTitle = 'Использовать'
      ..reviewScreenTitle = 'Предпросмотр (%d)'
      ..reviewScreenPageCount = 'Страница %d/%d'
      ..reviewScreenAddButtonTitle = 'Добавить'
      ..reviewScreenRetakeButtonTitle = 'Переснять'
      ..reviewScreenCropButtonTitle = 'Обрезать'
      ..reviewScreenRotateButtonTitle = 'Повернуть'
      ..reviewScreenDeleteButtonTitle = 'Удалить'
      ..reviewScreenSubmitButtonTitle = 'Готово'
      ..cameraCancelAlertTitle = 'Отменить сканирование?'
      ..cameraCancelNoButtonTitle = 'Нет'
      ..cameraCancelYesButtonTitle = 'Да, отменить'
      ..cameraLimitReachedAlertTitle = 'Достигнут лимит страниц'
      ..cameraLimitReachedOkButtonTitle = 'ОК'
      ..croppingTopBarConfirmButtonTitle = 'Готово'
      ..croppingTopBarCancelButtonTitle = 'Отмена';

    return configuration;
  }

  String _scanbotImagePath(sb_doc.PageData page) {
    final rawPath =
        page.documentImageURI ??
        page.unfilteredDocumentImageURI ??
        page.originalImageURI;
    final uri = Uri.tryParse(rawPath);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return rawPath;
  }

  Future<void> _startScanbotPassportScan() async {
    if (!mounted ||
        _isScanbotPassportActive ||
        _selectedFeature != Feat.passport ||
        captureModeController.captureMode != 'Автоматически') {
      return;
    }

    final remaining = _passportMaxPages - _passportBatch.length;
    if (remaining <= 0) {
      AppNotification.show(
        context,
        message: AppLocalizations.of(context).camMaxPages,
        type: NotificationType.info,
      );
      return;
    }

    _isScanbotPassportActive = true;
    _scanbotPassportRetakeRequested = false;
    _cancelAutoCapture();

    setState(() {
      _isScanning = true;
      _isDocumentDetected = false;
      captureModeController.isScanning = true;
      captureModeController.isDocumentDetected = false;
    });

    try {
      await _stopLiveDocumentDetection();
      await _disposeCameraController();
      await ScanbotConfig.ensureInitialized();
      if (!mounted) return;

      final result = await sb.ScanbotSdkUiV2.startDocumentScanner(
        _scanbotPassportConfiguration(remaining),
      );
      if (!mounted) return;

      if (result.status == sb.OperationStatus.CANCELED) {
        captureModeController.setCaptureMode('Вручную');
        return;
      }
      if (result.status == sb.OperationStatus.ERROR) {
        throw StateError(result.errorMessage ?? 'Ошибка Scanbot');
      }

      final document = result.data;
      if (document == null) {
        throw StateError('Scanbot не вернул документ');
      }
      final scannedFiles = <XFile>[];
      for (final page in document.pages.take(remaining)) {
        final path = _scanbotImagePath(page);
        if (path.isNotEmpty && await File(path).exists()) {
          scannedFiles.add(XFile(path));
        }
      }

      if (scannedFiles.isEmpty) {
        throw StateError('Scanbot не вернул обработанные страницы');
      }
      if (!mounted) return;

      setState(() => _passportBatch.addAll(scannedFiles));
      await _finishPassportBatch(scanbotFlow: true);
    } catch (error) {
      if (mounted) {
        captureModeController.setCaptureMode('Вручную');
        AppNotification.show(
          context,
          message: '${AppLocalizations.of(context).commonError}: $error',
          type: NotificationType.error,
        );
      }
    } finally {
      final shouldRetake = _scanbotPassportRetakeRequested;
      _scanbotPassportRetakeRequested = false;
      _isScanbotPassportActive = false;

      if (mounted) {
        setState(() {
          _isScanning = false;
          captureModeController.isScanning = false;
        });

        if (shouldRetake &&
            _selectedFeature == Feat.passport &&
            captureModeController.captureMode == 'Автоматически') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_startScanbotPassportScan());
          });
        } else {
          await _initializeCamera();
        }
      }
    }
  }

  String _passportOverlayLabel(AppLocalizations l10n) {
    // Подсказка называет СЛЕДУЮЩУЮ страницу по порядку: «Первая страница»,
    // «Вторая страница»… Когда буфер полон — показываем итоговое количество.
    if (_passportBatch.length >= _passportMaxPages) {
      return l10n.camPassportPages(_passportBatch.length);
    }
    return l10n.camPassportNextPage('${_passportBatch.length + 1}');
  }

  /// «Готово» в режиме паспорта: открывает превью всех накопленных страниц.
  Future<void> _finishPassportBatch({bool scanbotFlow = false}) async {
    if (_passportBatch.isEmpty || !mounted) return;
    final readyFiles = List<XFile>.from(_passportBatch);
    await _openPreview(
      imageFiles: readyFiles,
      isTwoPage: readyFiles.length > 1,
      onRetake: () {
        // «Переснять» = начать паспорт заново: чистим буфер и возвращаемся.
        if (scanbotFlow) {
          _scanbotPassportRetakeRequested = true;
        }
        Navigator.pop(context);
        _resetTwoPageState();
        if (!scanbotFlow) {
          _startDocumentDetectionStream();
        }
      },
      restartDetectionOnReturn: false,
    );
    if (!mounted) return;
    _resetTwoPageState();
    setState(() {
      _isScanning = false;
      captureModeController.isScanning = false;
    });
    if (!scanbotFlow) {
      _startDocumentDetectionStream();
    } else if (!_scanbotPassportRetakeRequested) {
      // После закрытия превью ручной режим остаётся рабочим, а повторный
      // выбор «Авто» снова открывает Scanbot.
      captureModeController.setCaptureMode('Вручную');
    }
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
        // Сканируем в буфер до свободного лимита; превью откроет галочка.
        final remaining = _passportMaxPages - _passportBatch.length;
        if (remaining <= 0) {
          AppNotification.show(
            context,
            message: l10n.camMaxPages,
            type: NotificationType.info,
          );
          return;
        }
        scannedFiles = await _scanImagesWithNativeScanner(pageLimit: remaining);
        if (scannedFiles.isEmpty || !mounted) return;

        final passportFiles = <XFile>[];
        for (final scannedFile in scannedFiles.take(remaining)) {
          passportFiles.add(await _autoCropPassportXFile(scannedFile));
          if (!mounted) return;
        }

        setState(() => _passportBatch.addAll(passportFiles));
        AppNotification.show(
          context,
          message: l10n.camPageAdded(_passportBatch.length),
          type: NotificationType.success,
        );
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

    _captureFrameBounds = _autoFrameBounds[_selectedFeature];
    _captureFrameFeature = _selectedFeature;
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
        final useAutoCrop =
            captureModeController.captureMode == 'Автоматически';
        final ecoImage = useAutoCrop
            ? await _autoCropDocumentXFile(file)
            : file;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                EcoPackagingScreen(initialImage: File(ecoImage.path)),
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
        // Свободный буфер: страницы копятся до лимита, превью открывает
        // пользователь галочкой (см. _finishPassportBatch).
        if (_passportBatch.length >= _passportMaxPages) {
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

        final passportImage = await _autoCropPassportXFile(file);
        if (!mounted) return;
        setState(() => _passportBatch.add(passportImage));

        _lastPassportCaptureBounds =
            _captureFrameBounds ?? _autoFrameBounds[Feat.passport];
        _isScanning = false;
        captureModeController.isScanning = false;
        _awaitDocumentExit = true;
        _startDocumentDetectionStream();
        AppNotification.show(
          context,
          message: l10n.camPageAdded(_passportBatch.length),
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
      if (_passportBatch.length >= _passportMaxPages) {
        AppNotification.show(
          context,
          message: AppLocalizations.of(context).camMaxPages,
          type: NotificationType.info,
        );
        _startDocumentDetectionStream();
        return;
      }

      final passportImage = await _autoCropPassportXFile(galleryImage);
      if (!mounted) return;

      setState(() => _passportBatch.add(passportImage));
      AppNotification.show(
        context,
        message: AppLocalizations.of(
          context,
        ).camPageAdded(_passportBatch.length),
        type: NotificationType.success,
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

  void _scrollToSelectedFeature([int attempt = 0]) {
    if (!mounted || attempt > 4) return;

    final index = _features.indexWhere((f) => f['name'] == _selectedFeature);
    if (index == -1) return;

    if (!_featureScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _featureScrollController.hasClients) {
          _scrollToSelectedFeature(attempt + 1);
        }
      });
      return;
    }

    // Слоты одинаковой ширины (1/6 капсулы): центрируем выбранного
    // арифметикой, округляя к сетке слотов — по краям не остаётся
    // обрезанных иконок.
    final pos = _featureScrollController.position;
    final double slot = _featureSlotWidth;
    final double raw = index * slot + slot / 2 - pos.viewportDimension / 2;
    final double snapped = (raw / slot).roundToDouble() * slot;
    final double target = snapped.clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );
    _isInitialScrollDone = true;
    _featureScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
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

  bool _manualFrameRotationEnabled(String featureName) {
    return featureName == Feat.passport ||
        featureName == Feat.restorePhoto ||
        featureName == Feat.removeSpots ||
        featureName == Feat.removeWatermark ||
        featureName == Feat.eco ||
        featureName == Feat.document ||
        featureName == Feat.plus10Pages;
  }

  bool _compactLandscapeFrame(String featureName) {
    return featureName != Feat.passport &&
        _manualFrameRotationEnabled(featureName);
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
      case Feat.passport:
        return l10n.camChipPassport;
      case Feat.idCard:
        return l10n.camChipIdCard;
      case Feat.document:
        return l10n.camChipDocument;
      case Feat.qrScanner:
        return l10n.camChipQr;
      case Feat.plus10Pages:
        return l10n.camChip10Pages;
      case Feat.translate:
        return l10n.camChipTranslate;
      case Feat.signature:
        return l10n.camChipSignature;
      case Feat.restorePhoto:
        return l10n.camChipRestore;
      case Feat.removeSpots:
        return l10n.camChipRemoveSpots;
      case Feat.highlight:
        return l10n.camChipHighlight;
      case Feat.ocr:
        return l10n.camChipOcr;
      case Feat.removeWatermark:
        return l10n.camChipNoWatermark;
      case Feat.addPassword:
        return l10n.camChipPassword;
      case Feat.eco:
        return l10n.camChipEco;
      default:
        return (feature['label'] ?? feature['name']) as String;
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
    //
    // Геометрия рамки считается явно (а не через Align), потому что то же
    // окно нужно вырезать из слоя затемнения и в нём же гонять линию
    // сканирования. Позиция повторяет прежний Align(0, -0.25).
    final Size screen = MediaQuery.of(context).size;
    final double frameSide = screen.width * 0.66;
    final Rect frameRect = Rect.fromLTWH(
      (screen.width - frameSide) / 2,
      (screen.height - frameSide) * 0.375,
      frameSide,
      frameSide,
    );
    final bool qrFound = _qrCode != null;

    return Stack(
      children: [
        // Затемнение вокруг окна рисует общий постоянный слой камеры
        // (вырез морфится между режимами и не мигает при переключении).

        // Рамка-видоискатель: белая в поиске, зелёная когда QR найден.
        Positioned.fromRect(
          rect: frameRect,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              decoration: BoxDecoration(
                border: Border.all(
                  color: qrFound ? Colors.greenAccent : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: qrFound
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),

        // Бегущая линия сканирования — пока код не найден.
        if (!qrFound)
          Positioned.fromRect(
            rect: frameRect.deflate(8),
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AnimatedBuilder(
                  animation: _qrScanLineCtrl,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_qrScanLineCtrl.value);
                    return Align(
                      alignment: Alignment(0, t * 2 - 1),
                      child: Container(
                        height: 2.6,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0x0035B4F4),
                              const Color(0xFF35B4F4),
                              Colors.white.withValues(alpha: 0.9),
                              const Color(0xFF35B4F4),
                              const Color(0x0035B4F4),
                            ],
                            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF35B4F4,
                              ).withValues(alpha: 0.55),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
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

        // Верхняя панель: назад + фонарик (единая с остальными режимами).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: CameraTopPanel(
            onBack: () => Navigator.pop(context),
            cameraController: _cameraController,
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

  static const double _kFeaturePanelHeight = 64;
  static const double _kFeaturePanelRadius = 32;
  static const double _kFeatureHorizontalInset = 6;
  static const double _kFeatureGlowWidth = 60;
  static const double _kFeatureGlowHeight = 50;
  static const double _kFeatureGlowRadius = 32;

  /// Ширина слота иконки: ровно 1/6 внутренней ширины капсулы — в панели
  /// видно ШЕСТЬ целых иконок, по краям нет обрезков. Обновляется в build
  /// (LayoutBuilder), используется снапом и центрированием.
  double _featureSlotWidth = 64;

  /// Идёт ли программная докрутка ленты (защита от повторного снапа).
  bool _isSnapAnimating = false;

  /// «Магнит»: после отпускания лента докручивается к сетке слотов —
  /// в видимой области остаются только целые иконки.
  void _snapFeatureScroll() {
    if (_isSnapAnimating || !_featureScrollController.hasClients) return;
    final pos = _featureScrollController.position;
    final double current = pos.pixels;

    final double target =
        ((current / _featureSlotWidth).roundToDouble() * _featureSlotWidth)
            .clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((target - current).abs() < 1) return;

    _isSnapAnimating = true;
    _featureScrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _isSnapAnimating = false);
  }

  Widget _buildFeatureSelector() {
    final l10n = AppLocalizations.of(context);
    final selIndex = _features.indexWhere((f) => f['name'] == _selectedFeature);

    return LayoutBuilder(
      builder: (context, constraints) =>
          _buildFeatureSelectorBody(l10n, selIndex, constraints.maxWidth),
    );
  }

  Widget _buildFeatureSelectorBody(
    AppLocalizations l10n,
    int selIndex,
    double totalWidth,
  ) {
    // Слот = 1/6 внутренней ширины капсулы (общая ширина минус боковые
    // отступы 16+16 и рамка 1+1): в панели видно ровно шесть целых иконок.
    _featureSlotWidth = (totalWidth - 34 - _kFeatureHorizontalInset * 2) / 5;

    Widget buildItem(int index) {
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
          HapticFeedback.selectionClick();
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

            if (newFeature == Feat.passport &&
                captureModeController.captureMode == 'Автоматически') {
              Future.delayed(const Duration(milliseconds: 350), () {
                if (mounted && _selectedFeature == Feat.passport) {
                  unawaited(_startScanbotPassportScan());
                }
              });
            } else if (newFeature != Feat.translate && newFeature != Feat.ocr) {
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
          key: _featureKeys[index],
          width: _featureSlotWidth,
          height: _kFeaturePanelHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: AnimatedScale(
                  scale: isSelected ? 1.0 : 0.9,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: isSelected ? 1.0 : 0.78,
                    child: Icon(
                      feature['icon'] as IconData? ?? Icons.circle,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (isPremiumFeature)
                // Компактный бейдж-кружок целиком внутри слота: не
                // обрезается краем капсулы и читается поверх подсветки.
                Positioned(
                  right: 7,
                  top: 6,
                  child: Container(
                    width: 15,
                    height: 15,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFD54F), Color(0xFFFF9800)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Название выбранного режима — НАД панелью (между панелью и затвором
        // ему тесно), со сменой через fade+slide.
        SizedBox(
          height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.4),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              selIndex < 0 ? '' : _featureLabel(_features[selIndex], l10n),
              key: ValueKey<String>(_selectedFeature),
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Стеклянная капсула: blur-подложка, внутри иконки режимов и
        // скользящая градиентная подсветка под выбранной.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Тень — на внешнем контейнере (внутри ClipRRect она бы обрезалась):
          // капсула заметнее отделяется от превью.
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_kFeaturePanelRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kFeaturePanelRadius),
              child: BackdropFilter(
                // Sigma умеренная: blur считается на каждом кадре превью,
                // высокие значения дают заметный лаг камеры на слабых GPU.
                filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: Container(
                  height: _kFeaturePanelHeight,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(_kFeaturePanelRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.26),
                    ),
                  ),
                  child: NotificationListener<ScrollEndNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis == Axis.horizontal) {
                        // Отложенно: в момент ScrollEnd позиция ещё
                        // завершает баллистику, и синхронный animateTo из
                        // колбэка молча проглатывается переходом в idle.
                        Future(() {
                          if (mounted) _snapFeatureScroll();
                        });
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _featureScrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: _kFeatureHorizontalInset,
                      ),
                      child: Stack(
                        children: [
                          // Подсветка «перетекает» к выбранной иконке: градиент,
                          // стеклянный блик сверху и пульсирующее свечение.
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 320),
                            // Без overshoot: подсветка встаёт точно в слот,
                            // не «переезжая» соседнюю иконку.
                            curve: Curves.easeOutCubic,
                            left:
                                (selIndex < 0 ? 0 : selIndex) *
                                    _featureSlotWidth +
                                (_featureSlotWidth - _kFeatureGlowWidth) / 2,
                            // -2: рамка капсулы (1px сверху и снизу) съедает
                            // высоту Stack — иначе подсветка смещена вниз на 1px.
                            top:
                                (_kFeaturePanelHeight -
                                    2 -
                                    _kFeatureGlowHeight) /
                                2,
                            width: _kFeatureGlowWidth,
                            height: _kFeatureGlowHeight,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: selIndex < 0 ? 0 : 1,
                              child: AnimatedBuilder(
                                animation: _selectorPulseCtrl,
                                builder: (context, _) {
                                  final pulse = Curves.easeInOut.transform(
                                    _selectorPulseCtrl.value,
                                  );
                                  return DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        _kFeatureGlowRadius,
                                      ),
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0x263FC0FF),
                                          Color(0x1F1687D5),
                                          Color(0x120F5FA8),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF54C7FF,
                                        ).withValues(alpha: 0.85),
                                        width: 1.6,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF2CA5E0)
                                              .withValues(
                                                alpha: 0.18 + pulse * 0.12,
                                              ),
                                          blurRadius: 10 + pulse * 6,
                                          spreadRadius: pulse,
                                        ),
                                      ],
                                    ),
                                    // Блик-линза: светлое пятно сверху-слева.
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          _kFeatureGlowRadius,
                                        ),
                                        gradient: const RadialGradient(
                                          center: Alignment(-0.5, -0.6),
                                          radius: 1.1,
                                          colors: [
                                            Color(0x24FFFFFF),
                                            Color(0x00FFFFFF),
                                          ],
                                          stops: [0.0, 0.55],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < _features.length; i++)
                                buildItem(i),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

    // Ранней ветки с лоадером больше нет: сплеш инициализации рисуется
    // ПОВЕРХ основного стека и плавно тает, когда превью готово (см. ниже) —
    // без резкой смены экранов.
    final Map<String, Widget Function()> featureViews = {
      Feat.passport: () => PassportCameraView(
        cameraController: _cameraController,
        captureModeController: captureModeController,
        isDocumentDetected: _isDocumentDetected,
        isScanning: _isScanning,
        pageModeLabel: _passportOverlayLabel(AppLocalizations.of(context)),
        capturedCount: _passportBatch.length,
        takePicture: _takePicture,
        onFinishBatch: _finishPassportBatch,
        resetTwoPageState: () {
          setState(_resetTwoPageState);
          _startDocumentDetectionStream();
        },
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
        resetIdCardState: () {
          setState(_resetIdCardState);
          _startDocumentDetectionStream();
        },
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
    final bool isQrSelected = _selectedFeature == Feat.qrScanner;
    // В QR нет нижнего бара с затвором — лента фильтров плавно съезжает
    // вниз (над историей сканов, если она есть) и так же плавно
    // возвращается при выборе другого режима.
    final double selectorBottom =
        MediaQuery.of(context).padding.bottom +
        (isQrSelected ? (_qrHistory.isNotEmpty ? 78.0 : 28.0) : 122.0);

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
          // ПОСТОЯННЫЙ слой рамки: затемнение, уголки, силуэт и подпись
          // рисуются здесь (а не в пофильтровых оверлеях), поэтому не мигают
          // при переключении — рамка плавно МОРФИТСЯ из формы одного режима
          // в форму другого, и рассинхрон затемнения с уголками невозможен.
          if (_cutoutSpecs.containsKey(_selectedFeature))
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart:
                    captureModeController.captureMode == 'Вручную' &&
                        _manualFrameRotationEnabled(_selectedFeature)
                    ? _startPassportFrameRotation
                    : null,
                onPanUpdate:
                    captureModeController.captureMode == 'Вручную' &&
                        _manualFrameRotationEnabled(_selectedFeature)
                    ? _updatePassportFrameRotation
                    : null,
                onPanEnd:
                    captureModeController.captureMode == 'Вручную' &&
                        _manualFrameRotationEnabled(_selectedFeature)
                    ? _finishPassportFrameRotation
                    : null,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final l10n = AppLocalizations.of(context);
                    final feature = _selectedFeature;
                    final spec = _cutoutSpecs[feature]!;
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    final isPassport = feature == Feat.passport;
                    final isManualFrame =
                        captureModeController.captureMode == 'Вручную';
                    final isRotatableManualFrame =
                        isManualFrame && _manualFrameRotationEnabled(feature);
                    final compactLandscape = _compactLandscapeFrame(feature);
                    final effectiveAspect = spec.aspect;
                    final effectiveWidthFactor = isRotatableManualFrame
                        ? spec.widthFactor +
                              (compactLandscape
                                  ? 0
                                  : 0.09 * math.sin(_passportManualAngle).abs())
                        : spec.widthFactor;
                    final frameW = w * effectiveWidthFactor;
                    final frameH = frameW / effectiveAspect;
                    final centerY =
                        h / 2 + spec.verticalAlignment * (h / 2 - frameH / 2);
                    Rect rect = Rect.fromCenter(
                      center: Offset(w / 2, centerY),
                      width: frameW,
                      height: frameH,
                    );
                    if (isPassport && !isManualFrame) {
                      rect = _mapAutoFrame(Size(w, h), feature) ?? rect;
                      rect = Rect.fromLTRB(
                        rect.left.clamp(12.0, w - 12.0),
                        rect.top,
                        rect.right.clamp(12.0, w - 12.0),
                        rect.bottom,
                      );
                    }
                    if (!isPassport &&
                        _frameDetectable(feature) &&
                        captureModeController.captureMode == 'Автоматически') {
                      rect = _mapAutoFrame(Size(w, h), feature) ?? rect;
                      rect = Rect.fromLTRB(
                        rect.left.clamp(12.0, w - 12.0),
                        rect.top,
                        rect.right.clamp(12.0, w - 12.0),
                        rect.bottom,
                      );
                    }
                    // На компактных экранах рамка может налезать на
                    // статус-карточку сверху или прижимать подпись к ленте
                    // фильтров снизу. Зажимаем её в доступную зону: сначала
                    // сдвиг, затем пропорциональное сжатие (аспект
                    // сохраняется). QR не трогаем — его рамка рисуется в
                    // собственном оверлее по своей формуле.
                    if (spec.brackets) {
                      // Верхний предел — под верхней панелью (Авто/Ручн.):
                      // статус-карточка временная и места не резервирует.
                      const double topLimit = 120;
                      final double bottomLimit =
                          h - MediaQuery.of(context).padding.bottom - 274;
                      if (rect.top < topLimit) {
                        rect = rect.shift(Offset(0, topLimit - rect.top));
                      }
                      if (rect.bottom > bottomLimit) {
                        final double maxH = bottomLimit - topLimit;
                        if (rect.height > maxH && maxH > 40) {
                          final rectAspect = rect.width / rect.height;
                          rect = Rect.fromCenter(
                            center: Offset(rect.center.dx, topLimit + maxH / 2),
                            width: maxH * rectAspect,
                            height: maxH,
                          );
                        } else {
                          rect = rect.shift(
                            Offset(0, bottomLimit - rect.bottom),
                          );
                        }
                      }
                      if (isRotatableManualFrame) {
                        final sine = math.sin(_passportManualAngle).abs();
                        final cosine = math.cos(_passportManualAngle).abs();
                        final rotatedHalfHeight =
                            (rect.width * sine + rect.height * cosine) / 2;
                        final rotatedTop = rect.center.dy - rotatedHalfHeight;
                        final rotatedBottom =
                            rect.center.dy + rotatedHalfHeight;
                        if (rotatedTop < topLimit) {
                          rect = rect.shift(Offset(0, topLimit - rotatedTop));
                        } else if (rotatedBottom > bottomLimit) {
                          rect = rect.shift(
                            Offset(0, bottomLimit - rotatedBottom),
                          );
                        }
                      }
                    }
                    if (isRotatableManualFrame) _passportFrameRect = rect;
                    final detected =
                        _frameDetectable(feature) && _isDocumentDetected;
                    final accent = detected
                        ? const Color(0xFF35D07F)
                        : Colors.white;
                    final icon = _frameIconFor(feature);
                    final hintText = detected
                        ? l10n.camDocDetectedHint
                        : _frameHintFor(feature, l10n);
                    return TweenAnimationBuilder<Rect?>(
                      tween: RectTween(end: rect),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      builder: (context, animated, _) {
                        final r = animated ?? rect;
                        final rotationDuration = _passportRotationDragActive
                            ? Duration.zero
                            : const Duration(milliseconds: 280);
                        final rotationScale = _manualRotationFitScale(
                          r,
                          _passportManualAngle,
                          compactLandscape: compactLandscape,
                        );
                        final rotatedFrameBottom = isRotatableManualFrame
                            ? r.center.dy +
                                  rotationScale *
                                      (r.width *
                                              math
                                                  .sin(_passportManualAngle)
                                                  .abs() +
                                          r.height *
                                              math
                                                  .cos(_passportManualAngle)
                                                  .abs()) /
                                      2
                            : r.bottom;
                        return Stack(
                          children: [
                            if (isRotatableManualFrame)
                              Positioned.fill(
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    end: _passportManualAngle,
                                  ),
                                  duration: rotationDuration,
                                  curve: Curves.easeOutCubic,
                                  builder: (context, angle, _) => CustomPaint(
                                    painter: _RotatedPassportFramePainter(
                                      cutout: r,
                                      angle: angle,
                                      color: accent,
                                      compactLandscape: compactLandscape,
                                    ),
                                  ),
                                ),
                              )
                            else
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _CutoutScrimPainter(cutout: r),
                                ),
                              ),
                            if (spec.brackets && !isRotatableManualFrame)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: CornerBracketsPainter(
                                    cutout: r,
                                    color: accent,
                                  ),
                                ),
                              ),
                            if (icon != null)
                              Positioned.fromRect(
                                rect: r,
                                child: Center(
                                  child: Icon(
                                    icon,
                                    size: r.height * 0.42,
                                    color: Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                              ),
                            if (hintText != null)
                              Positioned(
                                left: 24,
                                right: 24,
                                top: rotatedFrameBottom + 14,
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Container(
                                      key: ValueKey<String>(hintText),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        hintText,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: detected
                                              ? const Color(0xFF35D07F)
                                              : Colors.white.withValues(
                                                  alpha: 0.9,
                                                ),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          // Общие фоновые слои фильтров не пропускаем через AnimatedSwitcher:
          // два BackdropFilter при кроссфейде на мгновение меняли плотность и
          // резкость нижней подложки. Кнопки анимируются внутри
          // CameraControlsBar, а затемнённый фон остаётся визуально статичным.
          Positioned.fill(child: currentCameraView),
          AnimatedPositioned(
            // CameraControlsBar (child-view bottom-bar) уже включает
            // SafeArea и сам встаёт на bottom:0. Стеклянная панель висит над
            // ним с чётким зазором; при переходе в QR (нет бара с затвором)
            // лента плавно съезжает вниз и обратно.
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            bottom: selectorBottom,
            left: 0,
            right: 0,
            child: _buildFeatureSelector(),
          ),
          // Сплеш инициализации камеры: лежит поверх всего и плавно
          // растворяется, когда превью готово — вместо резкой смены
          // «лоадер → камера».
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _isCameraInitialized,
              child: AnimatedOpacity(
                opacity: _isCameraInitialized ? 0 : 1,
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOut,
                child: const _CameraBootSplash(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Экран запуска камеры: фирменный тёмный градиент и пульсирующая иконка
/// со свечением вместо голого белого спиннера.
class _CameraBootSplash extends StatefulWidget {
  const _CameraBootSplash();

  @override
  State<_CameraBootSplash> createState() => _CameraBootSplashState();
}

class _CameraBootSplashState extends State<_CameraBootSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final progress = _pulse.value;
        final breathe = (math.sin(progress * math.pi * 2) + 1) / 2;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0D1B2A), Color(0xFF10263B)],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: 0.98 + breathe * 0.035,
                  child: Container(
                    width: 116,
                    height: 116,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF172D41),
                      border: Border.all(
                        color: const Color(
                          0xFF35BDF8,
                        ).withValues(alpha: 0.55 + breathe * 0.25),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF20AEEF,
                          ).withValues(alpha: 0.12 + breathe * 0.10),
                          blurRadius: 26 + breathe * 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  l10n.camStarting,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: Colors.white.withValues(alpha: 0.10),
                    color: const Color(0xFF35BDF8),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
