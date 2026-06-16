import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/document_registry.dart';
import '../../../services/signature_storage_service.dart';
import '../signature/signature_pad.dart';

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

  PdfAnnotation? _currentAnnotation;
  Offset? _startPoint;
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

  bool get _isFreehandMode =>
      _currentMode == EditingMode.pen || _currentMode == EditingMode.highlight;

  bool get _hasSelectedSignature {
    final selected = _findAnnotation(_selectedAnnotationId);
    return selected?.type == EditingMode.signature;
  }

  String _newAnnotationId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

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
  }

  void _removeSelectedAnnotation() {
    final id = _selectedAnnotationId;
    if (id == null) return;
    setState(() {
      _annotations.removeWhere((annotation) => annotation.id == id);
      _selectedAnnotationId = null;
    });
  }

  void _rotateDocument() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _selectedAnnotationId = null;
    });
  }

  String _signatureTapHint(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Нажмите на документ, чтобы поставить подпись'
        : 'Tap the document to place the signature';
  }

  String _signatureCreateFirst(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Сначала создайте подпись'
        : 'Create a signature first';
  }

  String _signatureReadyMessage(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Подпись можно двигать и увеличивать'
        : 'You can drag and resize the signature';
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
                _saveDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.undo, color: Color(0xFF2CA5E0)),
              title: Text(
                l10n.pdfUndoLast,
                style: TextStyle(color: textColor),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _undoLastAction();
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

  Future<void> _saveDocument() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
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

      final dir = await getApplicationDocumentsDirectory();
      final baseName = widget.fileName.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${dir.path}/${baseName}_signed_$timestamp.pdf';
      await File(outPath).writeAsBytes(await pdf.save());
      await DocumentRegistry().load();
      await DocumentRegistry().add(
        DocEntry(
          localPath: outPath,
          remoteId: null,
          name: p.basenameWithoutExtension(outPath),
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).snackSaved(p.basename(outPath)))),
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
        if (_annotations.every((annotation) => annotation.id != _selectedAnnotationId)) {
          _selectedAnnotationId = null;
        }
      });
    }
  }

  void _clearAllAnnotations() {
    setState(() {
      _annotations.clear();
      _selectedAnnotationId = null;
      _currentMode = EditingMode.none;
    });
  }

  void _handlePanStart(DragStartDetails details) {
    if (!_isFreehandMode) return;

    _startPoint = details.localPosition;
    setState(() {
      _selectedAnnotationId = null;
      _currentAnnotation = PdfAnnotation(
        id: _newAnnotationId(),
        type: _currentMode,
        points: [_startPoint!],
        color: _selectedColor,
        strokeWidth: _strokeWidth,
      );
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_currentAnnotation == null || _startPoint == null) return;

    setState(() {
      _currentAnnotation = _currentAnnotation!.copyWith(
        points: [..._currentAnnotation!.points, details.localPosition],
      );
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_currentAnnotation != null) {
      setState(() {
        _annotations.add(_currentAnnotation!);
        _currentAnnotation = null;
        _startPoint = null;
      });
    }
  }

  Future<bool> _ensureSignatureReady() async {
    if (_signatureBytes != null) return true;

    final storedSignature = await _signatureStorage.loadSignature();
    if (storedSignature != null && storedSignature.isNotEmpty) {
      _signatureBytes = storedSignature;
      return true;
    }

    if (!mounted) return false;
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (!mounted || result == null) return false;

    await _signatureStorage.saveSignature(result);
    _signatureBytes = result;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_signatureCreateFirst(context))),
        );
        return;
      }

      setState(() {
        _currentMode = EditingMode.signature;
        _selectedAnnotationId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_signatureTapHint(context))),
      );
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
      }
      return;
    }

    final signatureBytes = _signatureBytes;
    if (signatureBytes == null) return;

    final renderBox = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final viewerSize = renderBox?.size;
    if (viewerSize == null) return;

    final originalSize = await _measureSignature(signatureBytes);
    if (!mounted) return;

    const targetWidth = 160.0;
    final aspectRatio =
        originalSize.width == 0 ? 2.8 : originalSize.width / originalSize.height;
    final width = targetWidth.clamp(110.0, viewerSize.width * 0.48);
    final height = (width / aspectRatio).clamp(40.0, 120.0);

    final left = (details.localPosition.dx - width / 2)
        .clamp(8.0, viewerSize.width - width - 8.0);
    final top = (details.localPosition.dy - height / 2)
        .clamp(8.0, viewerSize.height - height - 8.0);

    final annotation = PdfAnnotation(
      id: _newAnnotationId(),
      type: EditingMode.signature,
      points: const [],
      color: Colors.transparent,
      strokeWidth: 0,
      position: Offset(left, top),
      boxSize: Size(width, height),
      imageBytes: signatureBytes,
    );

    setState(() {
      _annotations.add(annotation);
      _selectedAnnotationId = annotation.id;
      _currentMode = EditingMode.none;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_signatureReadyMessage(context))),
    );
  }

  Offset _clampSignaturePosition({
    required Offset position,
    required Size boxSize,
    required Size viewerSize,
  }) {
    final dx = position.dx.clamp(8.0, viewerSize.width - boxSize.width - 8.0);
    final dy = position.dy.clamp(8.0, viewerSize.height - boxSize.height - 8.0);
    return Offset(dx, dy);
  }

  void _moveSignature(String id, Offset delta) {
    final renderBox = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final viewerSize = renderBox?.size;
    final annotation = _findAnnotation(id);
    if (viewerSize == null || annotation?.position == null || annotation?.boxSize == null) {
      return;
    }

    final nextPosition = _clampSignaturePosition(
      position: annotation!.position! + delta,
      boxSize: annotation.boxSize!,
      viewerSize: viewerSize,
    );
    _updateAnnotation(id, (current) => current.copyWith(position: nextPosition));
  }

  void _resizeSignature(String id, Offset delta) {
    final renderBox = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final viewerSize = renderBox?.size;
    final annotation = _findAnnotation(id);
    if (viewerSize == null || annotation?.position == null || annotation?.boxSize == null) {
      return;
    }

    final boxSize = annotation!.boxSize!;
    final aspectRatio = boxSize.width / boxSize.height;
    final nextWidth = (boxSize.width + delta.dx).clamp(90.0, viewerSize.width * 0.75);
    final nextHeight = (nextWidth / aspectRatio).clamp(34.0, viewerSize.height * 0.5);
    final nextSize = Size(nextWidth, nextHeight);
    final nextPosition = _clampSignaturePosition(
      position: annotation.position!,
      boxSize: nextSize,
      viewerSize: viewerSize,
    );

    _updateAnnotation(
      id,
      (current) => current.copyWith(position: nextPosition, boxSize: nextSize),
    );
  }

  Widget _buildSignatureAnnotation(PdfAnnotation annotation) {
    final position = annotation.position;
    final boxSize = annotation.boxSize;
    final imageBytes = annotation.imageBytes;
    if (position == null || boxSize == null || imageBytes == null) {
      return const SizedBox();
    }

    final isSelected = annotation.id == _selectedAnnotationId;
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: boxSize.width,
      height: boxSize.height,
      child: GestureDetector(
        onTap: () => setState(() => _selectedAnnotationId = annotation.id),
        onPanUpdate: (details) => _moveSignature(annotation.id, details.delta),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF2CA5E0)
                      : Colors.transparent,
                  width: 2,
                ),
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
                right: -10,
                bottom: -10,
                child: GestureDetector(
                  onPanUpdate: (details) => _resizeSignature(annotation.id, details.delta),
                  onTap: () {},
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
        return CustomPaint(painter: _AnnotationPainter(annotation));
      case EditingMode.signature:
        return _buildSignatureAnnotation(annotation);
      case EditingMode.none:
        return const SizedBox();
    }
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
                await Share.shareXFiles(
                  [XFile(widget.filePath)],
                  subject: widget.fileName,
                );
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
              child: GestureDetector(
                key: _viewerKey,
                onTapUp: _handleTapUp,
                onPanStart: _handlePanStart,
                onPanUpdate: _handlePanUpdate,
                onPanEnd: _handlePanEnd,
                child: PdfViewer.file(
                  widget.filePath,
                  params: PdfViewerParams(
                    backgroundColor: isDark
                        ? const Color(0xFF0F1923)
                        : const Color(0xFFF2F6FC),
                    loadingBannerBuilder: (
                      context,
                      bytesDownloaded,
                      totalBytes,
                    ) =>
                        const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2CA5E0),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ..._annotations.map(_buildAnnotation),
            if (_currentAnnotation != null) _buildAnnotation(_currentAnnotation!),
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

enum EditingMode {
  none,
  pen,
  highlight,
  signature,
}

class PdfAnnotation {
  final String id;
  final EditingMode type;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final Offset? position;
  final Size? boxSize;
  final Uint8List? imageBytes;

  PdfAnnotation({
    required this.id,
    required this.type,
    required this.points,
    required this.color,
    required this.strokeWidth,
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
      position: position ?? this.position,
      boxSize: boxSize ?? this.boxSize,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }
}

class _AnnotationPainter extends CustomPainter {
  final PdfAnnotation annotation;

  _AnnotationPainter(this.annotation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = annotation.type == EditingMode.highlight
          ? annotation.color.withValues(alpha: 0.3)
          : annotation.color
      ..strokeWidth = annotation.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (annotation.points.length > 1) {
      final path = Path();
      path.moveTo(annotation.points[0].dx, annotation.points[0].dy);

      for (int i = 1; i < annotation.points.length; i++) {
        path.lineTo(annotation.points[i].dx, annotation.points[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
