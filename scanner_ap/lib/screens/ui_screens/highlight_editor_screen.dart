import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/app_localizations.dart';

/// Один штрих маркера (режим «Кисть»): точки в нормализованных координатах
/// страницы (0..1) и толщина как доля ширины.
class _Stroke {
  final Color color;
  final double width;
  final List<Offset> points;
  _Stroke(this.color, this.width, this.points);
}

/// Строка текста (режим «По тексту», OCR): нормализованный прямоугольник +
/// выбрана ли она и каким цветом.
class _TextLine {
  final Rect rect;
  bool selected = false;
  Color color = const Color(0xFFFFEB3B);
  _TextLine(this.rect);
}

const _markerColors = <Color>[
  Color(0xFFFFEB3B),
  Color(0xFF8BC34A),
  Color(0xFFFF6E9C),
  Color(0xFF4FC3F7),
  Color(0xFFFFB74D),
];

/// Редактор подсветки. По умолчанию режим зависит от типа файла: PDF — «по
/// тексту» (тап/свайп по распознанным строкам), изображение — «кисть»
/// (фрихенд). Режим можно переключить вручную; если в PDF не распознан текст —
/// автоматически включается кисть. Возвращает (через Navigator.pop) список
/// «впечённых» страниц как PNG-байты, либо null.
class HighlightEditorScreen extends StatefulWidget {
  final List<Uint8List> pages;
  final bool textMode; // дефолт: true для PDF, false для изображения
  const HighlightEditorScreen({
    super.key,
    required this.pages,
    required this.textMode,
  });

  @override
  State<HighlightEditorScreen> createState() => _HighlightEditorScreenState();
}

class _HighlightEditorScreenState extends State<HighlightEditorScreen> {
  final List<ui.Image?> _decoded = [];
  late final List<List<_Stroke>> _strokesPerPage;
  late final List<List<_TextLine>> _linesPerPage;
  late bool _textMode;
  int _pageIndex = 0;
  Color _color = _markerColors.first;
  double _width = 0.035;
  bool _saving = false;
  bool _recognizing = false;

  Rect _imgRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _textMode = widget.textMode;
    _strokesPerPage = List.generate(widget.pages.length, (_) => <_Stroke>[]);
    _linesPerPage = List.generate(widget.pages.length, (_) => <_TextLine>[]);
    _decoded.addAll(List<ui.Image?>.filled(widget.pages.length, null));
    _init();
  }

  Future<void> _init() async {
    for (var i = 0; i < widget.pages.length; i++) {
      try {
        final codec = await ui.instantiateImageCodec(widget.pages[i]);
        final frame = await codec.getNextFrame();
        if (!mounted) return;
        setState(() => _decoded[i] = frame.image);
      } catch (_) {}
    }
    if (!mounted) return;
    // OCR гоним всегда (нужны боксы строк) — это даёт текстовый режим и для
    // изображений с текстом, и кисть-фолбэк для PDF без текста.
    await _runOcr();
    if (!mounted) return;
    // PDF без распознанного текста → переключаемся на кисть.
    if (_textMode && _linesPerPage.every((lines) => lines.isEmpty)) {
      setState(() => _textMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).hlNoText)),
      );
    }
  }

  Future<void> _runOcr() async {
    setState(() => _recognizing = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final dir = await getTemporaryDirectory();
    try {
      for (var i = 0; i < widget.pages.length; i++) {
        final image = _decoded[i];
        if (image == null) continue;
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        final file = File(
          '${dir.path}/hlocr_${i}_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(widget.pages[i]);
        try {
          // Используем только boundingBox строк (положение), а не сам текст —
          // поэтому подсветка работает и для кириллицы (латинская модель
          // боксит строки, даже если транскрипция неточна).
          final recognized =
              await recognizer.processImage(InputImage.fromFilePath(file.path));
          final lines = <_TextLine>[];
          for (final block in recognized.blocks) {
            for (final line in block.lines) {
              final b = line.boundingBox;
              final rect = Rect.fromLTRB(
                (b.left / w).clamp(0.0, 1.0),
                (b.top / h).clamp(0.0, 1.0),
                (b.right / w).clamp(0.0, 1.0),
                (b.bottom / h).clamp(0.0, 1.0),
              );
              if (rect.width > 0.01 && rect.height > 0.005) {
                lines.add(_TextLine(rect));
              }
            }
          }
          if (mounted) setState(() => _linesPerPage[i] = lines);
        } catch (_) {}
        try {
          await file.delete();
        } catch (_) {}
      }
    } finally {
      await recognizer.close();
      if (mounted) setState(() => _recognizing = false);
    }
  }

  List<_Stroke> get _strokes => _strokesPerPage[_pageIndex];
  List<_TextLine> get _lines => _linesPerPage[_pageIndex];

  // --- Жесты: кисть ---
  void _onPanStart(DragStartDetails d) {
    final n = _normalize(d.localPosition);
    if (n == null) return;
    setState(() => _strokes.add(_Stroke(_color, _width, [n])));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_strokes.isEmpty) return;
    final n = _normalize(d.localPosition);
    if (n == null) return;
    setState(() => _strokes.last.points.add(n));
  }

  // --- Жесты: по тексту ---
  void _toggleLineAt(Offset local) {
    final n = _normalize(local);
    if (n == null) return;
    for (final line in _lines) {
      if (line.rect.contains(n)) {
        setState(() {
          line.selected = !line.selected;
          if (line.selected) line.color = _color;
        });
        return;
      }
    }
  }

  void _selectLineAt(Offset local) {
    final n = _normalize(local);
    if (n == null) return;
    for (final line in _lines) {
      if (line.rect.contains(n) && !line.selected) {
        setState(() {
          line.selected = true;
          line.color = _color;
        });
        return;
      }
    }
  }

  Offset? _normalize(Offset local) {
    if (_imgRect.width <= 0 || _imgRect.height <= 0) return null;
    return Offset(
      ((local.dx - _imgRect.left) / _imgRect.width).clamp(0.0, 1.0),
      ((local.dy - _imgRect.top) / _imgRect.height).clamp(0.0, 1.0),
    );
  }

  bool get _hasMarks =>
      _strokes.isNotEmpty || _lines.any((l) => l.selected);

  void _undo() {
    if (_textMode) {
      final idx = _lines.lastIndexWhere((l) => l.selected);
      if (idx >= 0) setState(() => _lines[idx].selected = false);
    } else if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    }
  }

  void _clear() {
    setState(() {
      if (_textMode) {
        for (final l in _lines) {
          l.selected = false;
        }
      } else {
        _strokes.clear();
      }
    });
  }

  // --- Отрисовка наложений: и строки, и штрихи (чтобы пометки не терялись
  // при переключении режима). ---
  void _drawOverlay(Canvas canvas, Rect rect, int page) {
    for (final line in _linesPerPage[page]) {
      if (!line.selected) continue;
      final paint = Paint()
        ..color = line.color.withValues(alpha: 0.4)
        ..blendMode = BlendMode.multiply;
      final r = Rect.fromLTRB(
        rect.left + line.rect.left * rect.width,
        rect.top + line.rect.top * rect.height,
        rect.left + line.rect.right * rect.width,
        rect.top + line.rect.bottom * rect.height,
      );
      canvas.drawRect(r, paint);
    }
    for (final s in _strokesPerPage[page]) {
      _drawStroke(canvas, s, rect);
    }
  }

  void _drawStroke(Canvas canvas, _Stroke s, Rect rect) {
    if (s.points.isEmpty) return;
    final paint = Paint()
      ..color = s.color.withValues(alpha: 0.4)
      ..strokeWidth = s.width * rect.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.multiply;
    if (s.points.length == 1) {
      final p = Offset(
        rect.left + s.points.first.dx * rect.width,
        rect.top + s.points.first.dy * rect.height,
      );
      canvas.drawPoints(ui.PointMode.points, [p], paint);
      return;
    }
    final path = Path();
    for (var i = 0; i < s.points.length; i++) {
      final p = Offset(
        rect.left + s.points[i].dx * rect.width,
        rect.top + s.points[i].dy * rect.height,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  Future<Uint8List?> _flatten(ui.Image image, int page) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    _drawOverlay(
      canvas,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      page,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = <Uint8List>[];
      for (var i = 0; i < widget.pages.length; i++) {
        final image = _decoded[i];
        if (image == null) {
          result.add(widget.pages[i]);
          continue;
        }
        final flat = await _flatten(image, i);
        result.add(flat ?? widget.pages[i]);
      }
      if (mounted) Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final image = _decoded.isNotEmpty ? _decoded[_pageIndex] : null;
    final multi = widget.pages.length > 1;
    final hasLines = _lines.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      appBar: AppBar(
        title: Text(l10n.highlightTitle),
        backgroundColor: const Color(0xFF141E2B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Переключатель режимов (по тексту ↔ кисть). Текст доступен, только
          // если на странице есть распознанные строки.
          IconButton(
            icon: Icon(_textMode ? Icons.brush : Icons.text_fields),
            tooltip: _textMode ? l10n.hlModeBrush : l10n.hlModeText,
            onPressed: (!_textMode && !hasLines)
                ? null
                : () => setState(() => _textMode = !_textMode),
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.hlUndo,
            onPressed: _hasMarks ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.hlClear,
            onPressed: _hasMarks ? _clear : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: image == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final box =
                            Size(constraints.maxWidth, constraints.maxHeight);
                        _imgRect = _containRect(
                          Size(image.width.toDouble(),
                              image.height.toDouble()),
                          box,
                        );
                        final canvas = CustomPaint(
                          size: box,
                          painter: _PagePainter(
                            image,
                            (c, r) => _drawOverlay(c, r, _pageIndex),
                          ),
                        );
                        return _textMode
                            ? GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (d) => _toggleLineAt(d.localPosition),
                                onPanUpdate: (d) =>
                                    _selectLineAt(d.localPosition),
                                child: canvas,
                              )
                            : GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: _onPanStart,
                                onPanUpdate: _onPanUpdate,
                                child: canvas,
                              );
                      },
                    ),
                  ),
          ),
          if (multi) _buildPager(),
          _buildToolbar(l10n),
        ],
      ),
    );
  }

  Widget _buildPager() {
    return Container(
      color: const Color(0xFF141E2B),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white),
            onPressed:
                _pageIndex > 0 ? () => setState(() => _pageIndex--) : null,
          ),
          Text(
            '${_pageIndex + 1} / ${widget.pages.length}',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white),
            onPressed: _pageIndex < widget.pages.length - 1
                ? () => setState(() => _pageIndex++)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141E2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, 12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _recognizing
                ? l10n.hlRecognizing
                : (_textMode ? l10n.hlTapHint : l10n.hlBrushHint),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final c in _markerColors) ...[
                _ColorDot(
                  color: c,
                  selected: c == _color,
                  onTap: () => setState(() => _color = c),
                ),
                const SizedBox(width: 12),
              ],
            ],
          ),
          if (!_textMode)
            Row(
              children: [
                const Icon(Icons.brush, color: Colors.white54, size: 20),
                Expanded(
                  child: Slider(
                    value: _width,
                    min: 0.012,
                    max: 0.08,
                    activeColor: const Color(0xFF2CA5E0),
                    onChanged: (v) => setState(() => _width = v),
                  ),
                ),
              ],
            )
          else
            const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2CA5E0),
                disabledBackgroundColor:
                    const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      l10n.actionDone,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

Rect _containRect(Size content, Size box) {
  final double scale =
      (box.width / content.width) < (box.height / content.height)
          ? box.width / content.width
          : box.height / content.height;
  final double w = content.width * scale;
  final double h = content.height * scale;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

class _PagePainter extends CustomPainter {
  final ui.Image image;
  final void Function(Canvas, Rect) overlay;

  _PagePainter(this.image, this.overlay);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _containRect(
      Size(image.width.toDouble(), image.height.toDouble()),
      size,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint(),
    );
    overlay(canvas, rect);
  }

  @override
  bool shouldRepaint(covariant _PagePainter old) => true;
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 3,
          ),
        ),
      ),
    );
  }
}
