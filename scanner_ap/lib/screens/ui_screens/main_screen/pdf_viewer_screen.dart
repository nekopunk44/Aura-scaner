import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

class PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const PdfViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late PdfControllerPinch pdfController;
  bool _isLoading = true;

  EditingMode _currentMode = EditingMode.none;
  final List<PdfAnnotation> _annotations = [];
  PdfAnnotation? _currentAnnotation;
  Offset? _startPoint;
  static const List<Color> _annotationPalette = [
    Color(0xFFE53935), // red
    Color(0xFFFFB300), // amber
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF000000), // black
  ];
  Color _selectedColor = _annotationPalette.first;
  final double _strokeWidth = 3.0;


  int _rotation = 0;

  final GlobalKey _captureKey = GlobalKey();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.filePath),
      );
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading PDF: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    pdfController.dispose();
    super.dispose();
  }

  void _rotateDocument() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
    });
  }

  void _showMoreOptions() {
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
            Container(width: 36, height: 4, decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.black12, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.save, color: const Color(0xFF2CA5E0)),
              title: Text('Сохранить изменения', style: TextStyle(color: textColor)),
              onTap: () { Navigator.pop(ctx); _saveDocument(); },
            ),
            ListTile(
              leading: Icon(Icons.undo, color: const Color(0xFF2CA5E0)),
              title: Text('Отменить последнее', style: TextStyle(color: textColor)),
              onTap: () { Navigator.pop(ctx); _undoLastAction(); },
            ),
            ListTile(
              leading: Icon(Icons.clear_all, color: Colors.red.shade400),
              title: Text('Очистить аннотации', style: TextStyle(color: textColor)),
              onTap: () { Navigator.pop(ctx); _clearAllAnnotations(); },
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
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Не удалось получить область захвата');
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('Не удалось закодировать изображение');
      }
      final pngBytes = byteData.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final baseName = widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${dir.path}/${baseName}_annotated_$timestamp.png';
      await File(outPath).writeAsBytes(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Сохранено: $outPath')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _undoLastAction() {
    if (_annotations.isNotEmpty) {
      setState(() {
        _annotations.removeLast();
      });
    }
  }

  void _clearAllAnnotations() {
    setState(() {
      _annotations.clear();
    });
  }

  void _handlePanStart(DragStartDetails details) {
    if (_currentMode == EditingMode.none) return;

    _startPoint = details.localPosition;

    setState(() {
      _currentAnnotation = PdfAnnotation(
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
          points: [..._currentAnnotation!.points, details.localPosition]
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

  Widget _buildAnnotation(PdfAnnotation annotation) {
    switch (annotation.type) {
      case EditingMode.highlight:
      case EditingMode.pen:
        return CustomPaint(
          painter: _AnnotationPainter(annotation),
        );
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
        title: Text(widget.fileName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: textColor),
            onPressed: () async {
              final file = File(widget.filePath);
              if (await file.exists()) {
                await Share.shareXFiles([XFile(widget.filePath)], subject: widget.fileName);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : RepaintBoundary(
              key: _captureKey,
              child: Stack(
                children: [
                  Transform.rotate(
                    angle: _rotation * 3.14159 / 180,
                    child: GestureDetector(
                      onPanStart: _handlePanStart,
                      onPanUpdate: _handlePanUpdate,
                      onPanEnd: _handlePanEnd,
                      child: PdfViewPinch(controller: pdfController),
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
    final toolbarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final activeColor = const Color(0xFF2CA5E0);
    final inactiveColor = isDark ? Colors.white38 : Colors.black45;
    final showColors = _currentMode != EditingMode.none;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: toolbarBg,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE8EDF5))),
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
                  for (final c in _annotationPalette)
                    GestureDetector(
                      onTap: () => setState(() => _selectedColor = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == c ? activeColor : Colors.transparent,
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
                _buildToolbarButton(icon: Icons.rotate_right, label: 'Повернуть', isActive: false, activeColor: activeColor, inactiveColor: inactiveColor, onTap: _rotateDocument),
                _buildToolbarButton(
                  icon: Icons.edit,
                  label: 'Ручка',
                  isActive: _currentMode == EditingMode.pen,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _currentMode = _currentMode == EditingMode.pen ? EditingMode.none : EditingMode.pen),
                ),
                _buildToolbarButton(
                  icon: Icons.highlight,
                  label: 'Выделить',
                  isActive: _currentMode == EditingMode.highlight,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () => setState(() => _currentMode = _currentMode == EditingMode.highlight ? EditingMode.none : EditingMode.highlight),
                ),
                _buildToolbarButton(icon: Icons.more_vert, label: 'Ещё', isActive: false, activeColor: activeColor, inactiveColor: inactiveColor, onTap: _showMoreOptions),
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
            Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
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
}

class PdfAnnotation {
  final EditingMode type;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  PdfAnnotation({
    required this.type,
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  PdfAnnotation copyWith({
    EditingMode? type,
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
  }) {
    return PdfAnnotation(
      type: type ?? this.type,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
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