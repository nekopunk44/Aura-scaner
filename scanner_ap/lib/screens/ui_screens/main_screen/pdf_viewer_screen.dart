import 'dart:io';
import 'package:flutter/material.dart';
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
  final Color _selectedColor = Colors.red;
  final double _strokeWidth = 3.0;


  int _rotation = 0;

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
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('Обрезать документ'),
              onTap: () {
                Navigator.pop(context);
                _showCropDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.save),
              title: const Text('Сохранить изменения'),
              onTap: () {
                Navigator.pop(context);
                _saveDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Отменить последнее действие'),
              onTap: () {
                Navigator.pop(context);
                _undoLastAction();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Очистить все аннотации'),
              onTap: () {
                Navigator.pop(context);
                _clearAllAnnotations();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCropDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обрезать документ'),
        content: const Text('Функция обрезки будет реализована в следующей версии'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _saveDocument() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Изменения сохранены')),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
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
      bottomNavigationBar: _buildToolbar(),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildToolbarButton(
            icon: Icons.rotate_right,
            label: 'Повернуть',
            isActive: false,
            onTap: _rotateDocument,
          ),
          _buildToolbarButton(
            icon: Icons.edit,
            label: 'Ручка',
            isActive: _currentMode == EditingMode.pen,
            onTap: () => setState(() {
              _currentMode = _currentMode == EditingMode.pen ? EditingMode.none : EditingMode.pen;
            }),
          ),
          _buildToolbarButton(
            icon: Icons.highlight,
            label: 'Выделить',
            isActive: _currentMode == EditingMode.highlight,
            onTap: () => setState(() {
              _currentMode = _currentMode == EditingMode.highlight ? EditingMode.none : EditingMode.highlight;
            }),
          ),
          _buildToolbarButton(
            icon: Icons.draw,
            label: 'Подпись',
            isActive: false,
            onTap: () => _showSignatureDialog(),
          ),
          _buildToolbarButton(
            icon: Icons.more_vert,
            label: 'Еще',
            isActive: false,
            onTap: _showMoreOptions,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          color: isActive ? Colors.blue : Colors.black54,
          onPressed: onTap,
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? Colors.blue : Colors.black54,
          ),
        ),
      ],
    );
  }

  void _showSignatureDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить подпись'),
        content: const Text('Функция добавления подписи будет реализована в следующей версии'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
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