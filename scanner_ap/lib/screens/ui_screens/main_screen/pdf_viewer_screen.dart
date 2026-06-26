import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' hide PdfPage, PdfRect;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/document_registry.dart';
import '../../../services/signature_storage_service.dart';
import '../signature/signature_picker_sheet.dart';

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  EditingMode _currentMode = EditingMode.none;
  final List<PdfAnnotation> _annotations = [];
  final _signatureStorage = SignatureStorageService();
  final _pdfController = PdfViewerController();
  late final PdfViewerParams _pdfViewerParams;
  late final Widget _pdfViewerLayer;

  PdfAnnotation? _currentAnnotation;
  String? _selectedAnnotationId;
  Uint8List? _signatureBytes;

  static const List<Color> _annotationPalette = [
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF000000),
  ];
  Color _selectedColor = _annotationPalette.first;
  final double _strokeWidth = 3.0;

  int _rotation = 0;

  final GlobalKey _captureKey = GlobalKey();
  final GlobalKey _viewerKey = GlobalKey();
  bool _isSaving = false;
  bool _isPreparingSignature = false;
  bool _isDraggingSelectedSignature = false;
  bool _isResizingSelectedSignature = false;
  int? _activePointerId;

  void _refreshPdfOverlays() {
    if (_pdfController.isReady) {
      _pdfController.invalidate();
    }
  }

  @override
  void initState() {
    super.initState();
    _pdfViewerParams = PdfViewerParams(
      backgroundColor: Colors.transparent,
      pageOverlaysBuilder: _buildPageOverlays,
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) =>
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF2CA5E0)),
          ),
    );
    _pdfViewerLayer = PdfViewer.file(
      widget.filePath,
      controller: _pdfController,
      params: _pdfViewerParams,
    );
  }

  bool get _isFreehandMode =>
      _currentMode == EditingMode.pen || _currentMode == EditingMode.highlight;

  bool get _hasSelectedSignature {
    final selected = _findAnnotation(_selectedAnnotationId);
    return selected?.type == EditingMode.signature;
  }

  String _newAnnotationId() => DateTime.now().microsecondsSinceEpoch.toString();

  PdfAnnotation? _findAnnotation(String? id) {
    if (id == null) return null;
    try {
      return _annotations.firstWhere((annotation) => annotation.id == id);
    } catch (_) {
      return null;
    }
  }

  void _updateAnnotation(
    String id,
    PdfAnnotation Function(PdfAnnotation annotation) updater,
  ) {
    final index = _annotations.indexWhere((annotation) => annotation.id == id);
    if (index == -1) return;
    setState(() {
      _annotations[index] = updater(_annotations[index]);
    });
    _refreshPdfOverlays();
  }

  void _removeSelectedAnnotation() {
    final id = _selectedAnnotationId;
    if (id == null) return;
    setState(() {
      _annotations.removeWhere((annotation) => annotation.id == id);
      _selectedAnnotationId = null;
    });
    _refreshPdfOverlays();
  }

  void _rotateDocument() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _selectedAnnotationId = null;
    });
    _refreshPdfOverlays();
  }

  String _signatureTapHint(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Нажмите на документ, чтобы поставить подпись'
        : 'Tap the document to place the signature';
  }

  String _signatureSelectedLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Подпись'
        : 'Signature';
  }

  void _showMoreOptions() {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.save, color: Color(0xFF2CA5E0)),
              title: Text(
                l10n.pdfSaveChanges,
                style: TextStyle(color: textColor),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _saveDocument(saveAsCopy: false);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.copy_outlined,
                color: Color(0xFF2CA5E0),
              ),
              title: Text(
                Localizations.localeOf(context).languageCode == 'ru'
                    ? 'Сохранить как копию'
                    : 'Save as copy',
                style: TextStyle(color: textColor),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _saveDocument(saveAsCopy: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.undo, color: Color(0xFF2CA5E0)),
              title: Text(l10n.pdfUndoLast, style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(ctx);
                _undoLastAction();
              },
            ),
            if (_rotation != 0)
              ListTile(
                leading: const Icon(
                  Icons.screen_rotation_alt,
                  color: Color(0xFF2CA5E0),
                ),
                title: Text(
                  Localizations.localeOf(context).languageCode == 'ru'
                      ? 'Сбросить поворот'
                      : 'Reset rotation',
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _rotation = 0);
                  _refreshPdfOverlays();
                },
              ),
            if (_hasSelectedSignature)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
                title: Text(
                  l10n.actionDelete,
                  style: TextStyle(color: textColor),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeSelectedAnnotation();
                },
              ),
            ListTile(
              leading: Icon(Icons.clear_all, color: Colors.red.shade400),
              title: Text(
                l10n.pdfClearAnnotations,
                style: TextStyle(color: textColor),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _clearAllAnnotations();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _buildAnnotatedPdfBytes() async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Capture area is unavailable');
    }

    final image = await boundary.toImage(pixelRatio: 2.0);
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw StateError('Could not encode image');
    }
    final pngBytes = byteData.buffer.asUint8List();

    final pdf = pw.Document();
    final imageProvider = pw.MemoryImage(pngBytes);
    pdf.addPage(
      pw.Page(
        margin: pw.EdgeInsets.zero,
        pageFormat: PdfPageFormat(width, height),
        build: (_) => pw.SizedBox.expand(
          child: pw.Image(imageProvider, fit: pw.BoxFit.fill),
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> _saveDocument({required bool saveAsCopy}) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final pdfBytes = await _buildAnnotatedPdfBytes();

      final dir = await getApplicationDocumentsDirectory();
      final baseName = widget.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final outPath = saveAsCopy
          ? '${dir.path}/${baseName}_signed_${DateTime.now().millisecondsSinceEpoch}.pdf'
          : widget.filePath;
      await File(outPath).writeAsBytes(pdfBytes);
      if (saveAsCopy) {
        await DocumentRegistry().load();
        await DocumentRegistry().add(
          DocEntry(
            localPath: outPath,
            remoteId: null,
            name: p.basenameWithoutExtension(outPath),
          ),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).snackSaved(p.basename(outPath)),
          ),
        ),
      );
      Navigator.pop(context, outPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).pdfSaveFailed}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _undoLastAction() {
    if (_annotations.isNotEmpty) {
      setState(() {
        _annotations.removeLast();
        if (_annotations.every(
          (annotation) => annotation.id != _selectedAnnotationId,
        )) {
          _selectedAnnotationId = null;
        }
      });
      _refreshPdfOverlays();
    }
  }

  void _clearAllAnnotations() {
    setState(() {
      _annotations.clear();
      _selectedAnnotationId = null;
      _currentMode = EditingMode.none;
    });
    _refreshPdfOverlays();
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_isFreehandMode) return;

    if (!_pdfController.isReady) return;
    final hit = _pdfController.getPdfPageHitTestResult(
      details.localPosition,
      useDocumentLayoutCoordinates: false,
    );
    if (hit == null) return;

    final page = hit.page;
    final pageRect = _pdfController.layout.pageLayouts[page.pageNumber - 1];
    final pageScale = pageRect.width / page.width;
    setState(() {
      _selectedAnnotationId = null;
      _currentAnnotation = PdfAnnotation(
        id: _newAnnotationId(),
        type: _currentMode,
        points: [Offset(hit.offset.x, hit.offset.y)],
        color: _selectedColor,
        strokeWidth: _strokeWidth / pageScale,
        pageNumber: page.pageNumber,
        pageSize: Size(page.width, page.height),
      );
    });
    _refreshPdfOverlays();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final annotation = _currentAnnotation;
    if (annotation == null || !_pdfController.isReady) return;
    final hit = _pdfController.getPdfPageHitTestResult(
      details.localPosition,
      useDocumentLayoutCoordinates: false,
    );
    if (hit == null || hit.page.pageNumber != annotation.pageNumber) return;

    setState(() {
      _currentAnnotation = annotation.copyWith(
        points: [...annotation.points, Offset(hit.offset.x, hit.offset.y)],
      );
    });
    _refreshPdfOverlays();
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_currentAnnotation != null) {
      setState(() {
        _annotations.add(_currentAnnotation!);
        _currentAnnotation = null;
      });
      _refreshPdfOverlays();
    }
  }

  Future<bool> _ensureSignatureReady() async {
    if (!mounted) return false;
    final picked = await SignaturePickerSheet.pickSignature(
      context,
      storage: _signatureStorage,
    );
    if (!mounted || picked == null) return false;
    _signatureBytes = picked;
    return true;
  }

  Future<Size> _measureSignature(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  Future<void> _toggleSignatureMode() async {
    if (_isPreparingSignature) return;
    if (_currentMode == EditingMode.signature) {
      setState(() => _currentMode = EditingMode.none);
      return;
    }

    setState(() => _isPreparingSignature = true);
    try {
      final ready = await _ensureSignatureReady();
      if (!mounted) return;
      if (!ready) {
        return;
      }

      setState(() {
        _currentMode = EditingMode.signature;
        _selectedAnnotationId = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isPreparingSignature = false);
      }
    }
  }

  Future<void> _handleTapUp(TapUpDetails details) async {
    if (_currentMode != EditingMode.signature || _isPreparingSignature) {
      if (_currentMode == EditingMode.none && _selectedAnnotationId != null) {
        setState(() => _selectedAnnotationId = null);
        _refreshPdfOverlays();
      }
      return;
    }

    final signatureBytes = _signatureBytes;
    if (signatureBytes == null) return;

    if (!_pdfController.isReady) return;

    final hit = _pdfController.getPdfPageHitTestResult(
      details.localPosition,
      useDocumentLayoutCoordinates: false,
    );
    if (hit == null) return;

    final originalSize = await _measureSignature(signatureBytes);
    if (!mounted) return;

    final page = hit.page;
    final pageRect = _pdfController.layout.pageLayouts[page.pageNumber - 1];
    final pageScale = pageRect.width / page.width;
    const targetWidth = 160.0;
    final aspectRatio = originalSize.width == 0
        ? 2.8
        : originalSize.width / originalSize.height;
    final widthOnScreen = targetWidth.clamp(110.0, pageRect.width * 0.48);
    final width = widthOnScreen / pageScale;
    final height = width / aspectRatio;
    final pageSize = Size(page.width, page.height);
    final position = _clampSignaturePositionOnPage(
      position: Offset(hit.offset.x - width / 2, hit.offset.y - height / 2),
      boxSize: Size(width, height),
      pageSize: pageSize,
    );

    final annotation = PdfAnnotation(
      id: _newAnnotationId(),
      type: EditingMode.signature,
      points: const [],
      color: Colors.transparent,
      strokeWidth: 0,
      pageNumber: page.pageNumber,
      pageSize: pageSize,
      position: position,
      boxSize: Size(width, height),
      imageBytes: signatureBytes,
    );

    setState(() {
      _annotations.add(annotation);
      _selectedAnnotationId = annotation.id;
      _currentMode = EditingMode.none;
    });
    _refreshPdfOverlays();
  }

  Offset _clampSignaturePositionOnPage({
    required Offset position,
    required Size boxSize,
    required Size pageSize,
  }) {
    final dx = position.dx.clamp(0.0, pageSize.width - boxSize.width);
    final dy = position.dy.clamp(0.0, pageSize.height - boxSize.height);
    return Offset(dx, dy);
  }

  void _moveSignature(String id, Offset delta) {
    final annotation = _findAnnotation(id);
    if (annotation?.position == null ||
        annotation?.boxSize == null ||
        annotation?.pageNumber == null ||
        annotation?.pageSize == null ||
        !_pdfController.isReady) {
      return;
    }

    final pageRect =
        _pdfController.layout.pageLayouts[annotation!.pageNumber! - 1];
    final scaleX = pageRect.width / annotation.pageSize!.width;
    final scaleY = pageRect.height / annotation.pageSize!.height;
    final nextPosition = _clampSignaturePositionOnPage(
      position: annotation.position!.translate(
        delta.dx / scaleX,
        -delta.dy / scaleY,
      ),
      boxSize: annotation.boxSize!,
      pageSize: annotation.pageSize!,
    );
    _updateAnnotation(
      id,
      (current) => current.copyWith(position: nextPosition),
    );
  }

  void _resizeSignature(String id, Offset delta) {
    final annotation = _findAnnotation(id);
    if (annotation?.position == null ||
        annotation?.boxSize == null ||
        annotation?.pageNumber == null ||
        annotation?.pageSize == null ||
        !_pdfController.isReady) {
      return;
    }

    final pageSize = annotation!.pageSize!;
    final pageRect =
        _pdfController.layout.pageLayouts[annotation.pageNumber! - 1];
    final scaleX = pageRect.width / pageSize.width;
    final boxSize = annotation.boxSize!;
    final aspectRatio = boxSize.width / boxSize.height;
    final maxWidth = (pageSize.width * 0.75).clamp(90.0, pageSize.width);
    final nextWidth = (boxSize.width + delta.dx / scaleX).clamp(90.0, maxWidth);
    final nextHeight = (nextWidth / aspectRatio).clamp(
      34.0,
      pageSize.height * 0.5,
    );
    final nextSize = Size(nextWidth, nextHeight);
    final nextPosition = _clampSignaturePositionOnPage(
      position: annotation.position!,
      boxSize: nextSize,
      pageSize: pageSize,
    );

    _updateAnnotation(
      id,
      (current) => current.copyWith(position: nextPosition, boxSize: nextSize),
    );
  }

  Rect? _annotationRectInViewer(PdfAnnotation annotation) {
    final context = _viewerKey.currentContext;
    if (context == null ||
        annotation.pageNumber == null ||
        annotation.position == null ||
        annotation.boxSize == null ||
        !_pdfController.isReady) {
      return null;
    }

    final pdfRect = PdfRect(
      annotation.position!.dx,
      annotation.position!.dy + annotation.boxSize!.height,
      annotation.position!.dx + annotation.boxSize!.width,
      annotation.position!.dy,
    );
    final docRect = _pdfController.calcRectForRectInsidePage(
      pageNumber: annotation.pageNumber!,
      rect: pdfRect,
    );
    return _pdfController.doc2local.rectToLocal(context, docRect);
  }

  Rect? _selectedSignatureRectInViewer() {
    final selected = _findAnnotation(_selectedAnnotationId);
    if (selected?.type != EditingMode.signature) return null;
    return _annotationRectInViewer(selected!);
  }

  Rect? _selectedResizeHandleRect() {
    final rect = _selectedSignatureRectInViewer();
    if (rect == null) return null;
    return Rect.fromLTWH(rect.right - 18, rect.bottom - 18, 28, 28);
  }

  void _handleSelectedSignaturePointerDown(PointerDownEvent event) {
    final handleRect = _selectedResizeHandleRect();
    final rect = _selectedSignatureRectInViewer();
    final point = event.localPosition;

    if (!(rect?.contains(point) ?? false) &&
        !(handleRect?.contains(point) ?? false)) {
      if (_selectedAnnotationId != null) {
        setState(() => _selectedAnnotationId = null);
        _refreshPdfOverlays();
      }
      _activePointerId = null;
      _isDraggingSelectedSignature = false;
      _isResizingSelectedSignature = false;
      return;
    }

    _activePointerId = event.pointer;

    _isResizingSelectedSignature = handleRect?.contains(point) ?? false;
    _isDraggingSelectedSignature =
        !_isResizingSelectedSignature && (rect?.contains(point) ?? false);
  }

  void _handleSelectedSignaturePointerMove(PointerMoveEvent event) {
    final id = _selectedAnnotationId;
    if (id == null || _activePointerId != event.pointer) return;

    if (_isResizingSelectedSignature) {
      _resizeSignature(id, event.delta);
    } else if (_isDraggingSelectedSignature) {
      _moveSignature(id, event.delta);
    }
  }

  void _handleSelectedSignaturePointerUp(PointerEvent event) {
    if (_activePointerId != event.pointer) return;
    _isDraggingSelectedSignature = false;
    _isResizingSelectedSignature = false;
    _activePointerId = null;
  }

  Widget _buildPageSignatureAnnotation(
    PdfAnnotation annotation,
    Rect pageRect,
    PdfPage page,
  ) {
    final position = annotation.position;
    final boxSize = annotation.boxSize;
    final imageBytes = annotation.imageBytes;
    if (position == null || boxSize == null || imageBytes == null) {
      return const SizedBox();
    }

    final scaleX = pageRect.width / page.width;
    final scaleY = pageRect.height / page.height;
    final left = position.dx * scaleX;
    final top = (page.height - position.dy - boxSize.height) * scaleY;
    final width = boxSize.width * scaleX;
    final height = boxSize.height * scaleY;
    final isSelected = annotation.id == _selectedAnnotationId;
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (_selectedAnnotationId != annotation.id) {
            setState(() => _selectedAnnotationId = annotation.id);
            _refreshPdfOverlays();
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2CA5E0).withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2CA5E0)
                      : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF2CA5E0,
                          ).withValues(alpha: 0.18),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : const [],
              ),
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            if (isSelected)
              Positioned(
                left: 6,
                top: -16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2CA5E0),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2CA5E0).withValues(alpha: 0.25),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    _signatureSelectedLabel(context),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (isSelected)
              Positioned(
                right: -10,
                bottom: -10,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2CA5E0),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.open_in_full,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnotation(PdfAnnotation annotation) {
    switch (annotation.type) {
      case EditingMode.highlight:
      case EditingMode.pen:
        return const SizedBox();
      case EditingMode.signature:
        return const SizedBox();
      case EditingMode.none:
        return const SizedBox();
    }
  }

  List<Widget> _buildPageOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final pageAnnotations = _annotations
        .where((annotation) => annotation.pageNumber == page.pageNumber)
        .toList();
    final currentAnnotation = _currentAnnotation;
    final currentForPage =
        currentAnnotation != null &&
            currentAnnotation.pageNumber == page.pageNumber
        ? currentAnnotation
        : null;

    return [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _PageAnnotationPainter(
              annotations: pageAnnotations,
              currentAnnotation: currentForPage,
              page: page,
            ),
          ),
        ),
      ),
      ...pageAnnotations
          .where((annotation) => annotation.type == EditingMode.signature)
          .map(
            (annotation) =>
                _buildPageSignatureAnnotation(annotation, pageRect, page),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: textColor),
            onPressed: () async {
              final file = File(widget.filePath);
              if (await file.exists()) {
                await Share.shareXFiles([
                  XFile(widget.filePath),
                ], subject: widget.fileName);
              }
            },
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _captureKey,
        child: Stack(
          children: [
            Transform.rotate(
              angle: _rotation * 3.14159 / 180,
              child: SizedBox.expand(
                key: _viewerKey,
                child: ColoredBox(
                  color: isDark
                      ? const Color(0xFF0F1923)
                      : const Color(0xFFF2F6FC),
                  child: _pdfViewerLayer,
                ),
              ),
            ),
            if (_currentMode != EditingMode.none)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: _currentMode == EditingMode.signature
                      ? _handleTapUp
                      : null,
                  onPanStart: _isFreehandMode ? _handlePanStart : null,
                  onPanUpdate: _isFreehandMode ? _handlePanUpdate : null,
                  onPanEnd: _isFreehandMode ? _handlePanEnd : null,
                  child: const SizedBox.expand(),
                ),
              ),
            if (_currentMode == EditingMode.none && _hasSelectedSignature)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleSelectedSignaturePointerDown,
                  onPointerMove: _handleSelectedSignaturePointerMove,
                  onPointerUp: _handleSelectedSignaturePointerUp,
                  onPointerCancel: _handleSelectedSignaturePointerUp,
                  child: const SizedBox.expand(),
                ),
              ),
            if (_currentMode == EditingMode.signature)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF2CA5E0,
                          ).withValues(alpha: 0.22),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.touch_app_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _signatureTapHint(context),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ..._annotations.map(_buildAnnotation),
            if (_currentAnnotation != null)
              _buildAnnotation(_currentAnnotation!),
          ],
        ),
      ),
      bottomNavigationBar: _buildToolbar(isDark),
    );
  }

  Widget _buildToolbar(bool isDark) {
    final l10n = AppLocalizations.of(context);
    final toolbarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final activeColor = const Color(0xFF2CA5E0);
    final inactiveColor = isDark ? Colors.white38 : Colors.black45;
    final showColors = _isFreehandMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: toolbarBg,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : const Color(0xFFE8EDF5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showColors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in _annotationPalette)
                    GestureDetector(
                      onTap: () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == color
                                ? activeColor
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildToolbarButton(
                  icon: Icons.rotate_right,
                  label: l10n.toolRotate,
                  isActive: false,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: _rotateDocument,
                ),
                _buildToolbarButton(
                  icon: Icons.edit,
                  label: l10n.toolPen,
                  isActive: _currentMode == EditingMode.pen,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() {
                    _currentMode = _currentMode == EditingMode.pen
                        ? EditingMode.none
                        : EditingMode.pen;
                    _selectedAnnotationId = null;
                  }),
                ),
                _buildToolbarButton(
                  icon: Icons.highlight,
                  label: l10n.toolHighlight,
                  isActive: _currentMode == EditingMode.highlight,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() {
                    _currentMode = _currentMode == EditingMode.highlight
                        ? EditingMode.none
                        : EditingMode.highlight;
                    _selectedAnnotationId = null;
                  }),
                ),
                _buildToolbarButton(
                  icon: Icons.draw_outlined,
                  label: l10n.featSignature,
                  isActive: _currentMode == EditingMode.signature,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: _toggleSignatureMode,
                ),
                if (_hasSelectedSignature)
                  _buildToolbarButton(
                    icon: Icons.delete_outline,
                    label: l10n.actionDelete,
                    isActive: false,
                    activeColor: Colors.red.shade400,
                    inactiveColor: Colors.red.shade400,
                    onTap: _removeSelectedAnnotation,
                  )
                else
                  _buildToolbarButton(
                    icon: Icons.more_vert,
                    label: l10n.toolMore,
                    isActive: false,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: _showMoreOptions,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    final color = isActive ? activeColor : inactiveColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum EditingMode { none, pen, highlight, signature }

class PdfAnnotation {
  final String id;
  final EditingMode type;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final int? pageNumber;
  final Size? pageSize;
  final Offset? position;
  final Size? boxSize;
  final Uint8List? imageBytes;

  PdfAnnotation({
    required this.id,
    required this.type,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.pageNumber,
    this.pageSize,
    this.position,
    this.boxSize,
    this.imageBytes,
  });

  PdfAnnotation copyWith({
    String? id,
    EditingMode? type,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    int? pageNumber,
    Size? pageSize,
    Offset? position,
    Size? boxSize,
    Uint8List? imageBytes,
  }) {
    return PdfAnnotation(
      id: id ?? this.id,
      type: type ?? this.type,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      pageNumber: pageNumber ?? this.pageNumber,
      pageSize: pageSize ?? this.pageSize,
      position: position ?? this.position,
      boxSize: boxSize ?? this.boxSize,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }
}

class _PageAnnotationPainter extends CustomPainter {
  final List<PdfAnnotation> annotations;
  final PdfAnnotation? currentAnnotation;
  final PdfPage page;

  _PageAnnotationPainter({
    required this.annotations,
    required this.currentAnnotation,
    required this.page,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final annotation in [
      ...annotations.where(
        (annotation) =>
            annotation.type == EditingMode.pen ||
            annotation.type == EditingMode.highlight,
      ),
      if (currentAnnotation != null &&
          (currentAnnotation!.type == EditingMode.pen ||
              currentAnnotation!.type == EditingMode.highlight))
        currentAnnotation!,
    ]) {
      final strokeScale = size.width / page.width;
      final paint = Paint()
        ..color = annotation.type == EditingMode.highlight
            ? annotation.color.withValues(alpha: 0.3)
            : annotation.color
        ..strokeWidth = annotation.strokeWidth * strokeScale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (annotation.points.length > 1) {
        final path = Path();
        final first = annotation.points.first;
        path.moveTo(
          first.dx * size.width / page.width,
          (page.height - first.dy) * size.height / page.height,
        );

        for (int i = 1; i < annotation.points.length; i++) {
          final point = annotation.points[i];
          path.lineTo(
            point.dx * size.width / page.width,
            (page.height - point.dy) * size.height / page.height,
          );
        }

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
