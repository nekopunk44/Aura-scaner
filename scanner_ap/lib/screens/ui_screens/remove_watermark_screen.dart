import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

class RemoveWatermarkScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const RemoveWatermarkScreen({super.key, this.onSaved});

  @override
  State<RemoveWatermarkScreen> createState() => _RemoveWatermarkScreenState();
}

class _RemoveWatermarkScreenState extends State<RemoveWatermarkScreen> {
  File? _imageFile;
  img.Image? _srcImage;
  Uint8List? _previewBytes;

  // Selection in screen coords (relative to image display area)
  Offset? _selStart;
  Offset? _selEnd;
  bool _isDragging = false;
  bool _processing = false;

  // Image display rect within the stack
  final GlobalKey _imgKey = GlobalKey();
  Size? _displaySize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.featRemoveWatermark,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          if (_imageFile != null && !_processing)
            TextButton(
              onPressed: _pickImage,
              child: Text(l10n.wmChange, style: const TextStyle(color: Color(0xFF2CA5E0))),
            ),
        ],
      ),
      body: _imageFile == null
          ? _buildPicker(isDark, textColor, subColor)
          : _buildEditor(isDark, subColor),
    );
  }

  Widget _buildPicker(bool isDark, Color textColor, Color subColor) {
    final l10n = AppLocalizations.of(context);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_fix_high, color: Color(0xFF2CA5E0), size: 40),
            ),
            const SizedBox(height: 20),
            Text(l10n.wmTitle,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
            const SizedBox(height: 8),
            Text(l10n.wmInstructions,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: subColor, height: 1.5)),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildSourceButton(Icons.image_outlined, l10n.wmFromGallery, ImageSource.gallery),
                  Divider(height: 1, color: isDark ? Colors.white12 : const Color(0xFFE8EDF5)),
                  _buildSourceButton(Icons.camera_alt_outlined, l10n.wmTakePhoto, ImageSource.camera),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceButton(IconData icon, String label, ImageSource source) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _pickImageFrom(source),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF2CA5E0), size: 22),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(bool isDark, Color subColor) {
    final l10n = AppLocalizations.of(context);
    final hasSelection = _selStart != null && _selEnd != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            hasSelection
                ? l10n.wmApplyHint
                : l10n.wmDrawHint,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: subColor),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            return GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.memory(
                    _previewBytes!,
                    key: _imgKey,
                    fit: BoxFit.contain,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                  if (_selStart != null && _selEnd != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SelectionPainter(_selStart!, _selEnd!),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearSelection,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFDDE3ED)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l10n.clearSelection, style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (hasSelection && !_processing) ? _applyRemoval : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2CA5E0),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _processing
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(l10n.wmApply, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _processing ? null : _saveImage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l10n.actionSave),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() => _pickImageFrom(ImageSource.gallery);

  Future<void> _pickImageFrom(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    setState(() {
      _imageFile = File(picked.path);
      _srcImage = decoded;
      _previewBytes = bytes;
      _selStart = null;
      _selEnd = null;
    });
  }

  void _onPanStart(DragStartDetails d) {
    _updateDisplayRect();
    setState(() {
      _selStart = d.localPosition;
      _selEnd = d.localPosition;
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_isDragging) return;
    setState(() => _selEnd = d.localPosition);
  }

  void _onPanEnd(DragEndDetails d) {
    setState(() => _isDragging = false);
  }

  void _clearSelection() {
    setState(() { _selStart = null; _selEnd = null; });
  }

  void _updateDisplayRect() {
    final box = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _displaySize = box.size;
  }

  // Map screen rect → image pixel rect
  Rect? _screenToImageRect(Offset s, Offset e) {
    if (_srcImage == null || _displaySize == null) return null;
    _updateDisplayRect();

    final imgW = _srcImage!.width.toDouble();
    final imgH = _srcImage!.height.toDouble();
    final dispW = _displaySize!.width;
    final dispH = _displaySize!.height;

    // BoxFit.contain: image is centred, letterboxed
    final imgAspect = imgW / imgH;
    final dispAspect = dispW / dispH;
    double scaleW, scaleH, offsetX, offsetY;
    if (imgAspect > dispAspect) {
      scaleW = dispW / imgW;
      scaleH = scaleW;
      offsetX = 0;
      offsetY = (dispH - imgH * scaleH) / 2;
    } else {
      scaleH = dispH / imgH;
      scaleW = scaleH;
      offsetX = (dispW - imgW * scaleW) / 2;
      offsetY = 0;
    }

    double toImgX(double sx) => ((sx - offsetX) / scaleW).clamp(0, imgW).toDouble();
    double toImgY(double sy) => ((sy - offsetY) / scaleH).clamp(0, imgH).toDouble();

    final left = toImgX(s.dx < e.dx ? s.dx : e.dx);
    final top = toImgY(s.dy < e.dy ? s.dy : e.dy);
    final right = toImgX(s.dx > e.dx ? s.dx : e.dx);
    final bottom = toImgY(s.dy > e.dy ? s.dy : e.dy);
    if ((right - left) < 2 || (bottom - top) < 2) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Future<void> _applyRemoval() async {
    if (_srcImage == null || _selStart == null || _selEnd == null) return;
    final rect = _screenToImageRect(_selStart!, _selEnd!);
    if (rect == null) return;

    setState(() => _processing = true);
    final result = await _fillRegion(_srcImage!, rect);
    final encoded = img.encodeJpg(result, quality: 95);
    setState(() {
      _srcImage = result;
      _previewBytes = Uint8List.fromList(encoded);
      _selStart = null;
      _selEnd = null;
      _processing = false;
    });
  }

  static Future<img.Image> _fillRegion(img.Image src, Rect rect) async {
    final x = rect.left.round().clamp(0, src.width - 1);
    final y = rect.top.round().clamp(0, src.height - 1);
    final w = (rect.width.round()).clamp(1, src.width - x);
    final h = (rect.height.round()).clamp(1, src.height - y);

    final result = src.clone();

    // Sample border pixels to get average fill color
    int totalR = 0, totalG = 0, totalB = 0, count = 0;
    for (int bx = x; bx < x + w; bx++) {
      if (y > 0) { final p = src.getPixel(bx, y - 1); totalR += p.r.round(); totalG += p.g.round(); totalB += p.b.round(); count++; }
      if (y + h < src.height) { final p = src.getPixel(bx, y + h); totalR += p.r.round(); totalG += p.g.round(); totalB += p.b.round(); count++; }
    }
    for (int by = y; by < y + h; by++) {
      if (x > 0) { final p = src.getPixel(x - 1, by); totalR += p.r.round(); totalG += p.g.round(); totalB += p.b.round(); count++; }
      if (x + w < src.width) { final p = src.getPixel(x + w, by); totalR += p.r.round(); totalG += p.g.round(); totalB += p.b.round(); count++; }
    }
    if (count == 0) { totalR = 255; totalG = 255; totalB = 255; count = 1; }

    final avgR = (totalR / count).round();
    final avgG = (totalG / count).round();
    final avgB = (totalB / count).round();

    // Fill rectangle with average color
    for (int py = y; py < y + h; py++) {
      for (int px = x; px < x + w; px++) {
        result.setPixelRgba(px, py, avgR, avgG, avgB, 255);
      }
    }

    // Blur the filled region softly to blend with surroundings
    final blurred = img.gaussianBlur(result, radius: 6);
    // Composite blurred region back (only the filled area)
    for (int py = y; py < y + h; py++) {
      for (int px = x; px < x + w; px++) {
        result.setPixel(px, py, blurred.getPixel(px, py));
      }
    }
    return result;
  }

  Future<void> _saveImage() async {
    if (_srcImage == null || _previewBytes == null) return;
    setState(() => _processing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'nowatermark_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(_previewBytes!);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('saved_document_paths') ?? [];
      if (!paths.contains(path)) { paths.add(path); await prefs.setStringList('saved_document_paths', paths); }

      widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).savedPlain), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocalizations.of(context).commonError}: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}

class _SelectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  _SelectionPainter(this.start, this.end);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()
      ..color = Colors.blue.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill);
    canvas.drawRect(rect, Paint()
      ..color = const Color(0xFF2CA5E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.start != start || old.end != end;
}
