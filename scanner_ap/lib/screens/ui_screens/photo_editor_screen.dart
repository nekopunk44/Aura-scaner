import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import '../../l10n/app_localizations.dart';
import '../../services/document_registry.dart';

enum PhotoEditorTool { crop, brightness, contrast, bw, stamp, signature }

enum _CropHandle { tl, tr, bl, br, move }

class _StampStyle {
  final String label;
  final String? family;
  final FontWeight weight;
  final bool italic;
  const _StampStyle(this.label, this.family, this.weight, this.italic);
  FontStyle get fontStyle => italic ? FontStyle.italic : FontStyle.normal;
}

/// Текстовый штамп (дата/время/гео) поверх фото.
class _Stamp {
  String text;
  double fontFrac; // доля ширины базы
  int styleIndex;
  Color color;
  bool backdrop;
  Offset norm; // 0..1 левый-верхний угол
  _Stamp({
    required this.text,
    required this.fontFrac,
    required this.styleIndex,
    required this.color,
    required this.backdrop,
    required this.norm,
  });
  _Stamp copy() => _Stamp(
    text: text,
    fontFrac: fontFrac,
    styleIndex: styleIndex,
    color: color,
    backdrop: backdrop,
    norm: norm,
  );
}

/// Подпись-картинка (прозрачный PNG) поверх фото.
class _Sign {
  final Uint8List png;
  final ui.Image image;
  double widthFrac; // доля ширины базы
  Offset norm;
  _Sign({
    required this.png,
    required this.image,
    required this.widthFrac,
    required this.norm,
  });
  _Sign copy() =>
      _Sign(png: png, image: image, widthFrac: widthFrac, norm: norm);
}

class _Snapshot {
  final String basePath;
  final double brightness, contrast;
  final bool grayscale;
  final _Stamp? stamp;
  final _Sign? sign;
  const _Snapshot(
    this.basePath,
    this.brightness,
    this.contrast,
    this.grayscale,
    this.stamp,
    this.sign,
  );
}

/// Единый фоторедактор: кадрирование, цвет, штамп (дата/гео) и подпись на одном
/// экране — фото выбирается один раз, правки накладываются вместе, сохранение
/// одно. Есть отмена последнего действия (undo).
class PhotoEditorScreen extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onSaved;

  /// Набор доступных инструментов (по умолчанию все). Позволяет открыть
  /// редактор в «лёгком» режиме — например, только цвет + кадрирование.
  final List<PhotoEditorTool> tools;

  const PhotoEditorScreen({
    super.key,
    required this.imagePath,
    this.onSaved,
    this.tools = PhotoEditorTool.values,
  });

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  static const _accent = Color(0xFF2CA5E0);
  static const _stampColors = [
    Colors.white,
    Colors.black,
    Color(0xFFFFEB3B),
    Color(0xFF2CA5E0),
    Color(0xFFFF5252),
  ];

  String _basePath = '';
  ui.Image? _base;

  double _brightness = 0.0; // -0.5..0.5
  double _contrast = 1.0; // 0.5..2.0
  bool _grayscale = false;

  _Stamp? _stamp;
  _Sign? _sign;

  // Рамка обрезки в нормализованных координатах (0..1) текущего фото.
  Rect _cropRect = const Rect.fromLTRB(0, 0, 1, 1);
  _CropHandle? _dragHandle;

  late PhotoEditorTool _tool;
  bool _saving = false;
  bool _locating = false;

  final List<_Snapshot> _undo = [];
  final TextEditingController _stampCtrl = TextEditingController();

  List<_StampStyle> _styles(AppLocalizations l10n) => [
    _StampStyle(l10n.geoStyleNormal, null, FontWeight.w600, false),
    _StampStyle(l10n.geoStyleBold, null, FontWeight.w800, false),
    _StampStyle(l10n.geoStyleItalic, null, FontWeight.w600, true),
    _StampStyle(l10n.geoStyleSerif, 'serif', FontWeight.w600, false),
    _StampStyle(l10n.geoStyleMono, 'monospace', FontWeight.w700, false),
  ];

  @override
  void initState() {
    super.initState();
    _basePath = widget.imagePath;
    _tool = widget.tools.first;
    _loadBase();
  }

  @override
  void dispose() {
    _stampCtrl.dispose();
    _base?.dispose();
    _sign?.image.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final bytes = await File(_basePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _base = frame.image);
  }

  // ── Undo ──
  void _pushUndo() {
    _undo.add(
      _Snapshot(
        _basePath,
        _brightness,
        _contrast,
        _grayscale,
        _stamp?.copy(),
        _sign?.copy(),
      ),
    );
    if (_undo.length > 30) _undo.removeAt(0);
  }

  Future<void> _doUndo() async {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    final baseChanged = s.basePath != _basePath;
    setState(() {
      _basePath = s.basePath;
      _brightness = s.brightness;
      _contrast = s.contrast;
      _grayscale = s.grayscale;
      _stamp = s.stamp?.copy();
      _sign = s.sign?.copy();
    });
    _stampCtrl.text = _stamp?.text ?? '';
    if (baseChanged) await _loadBase();
  }

  List<double> _colorMatrix() {
    final c = _contrast;
    final b = _brightness * 255;
    if (_grayscale) {
      return [
        0.2126 * c, 0.7152 * c, 0.0722 * c, 0, b, //
        0.2126 * c, 0.7152 * c, 0.0722 * c, 0, b, //
        0.2126 * c, 0.7152 * c, 0.0722 * c, 0, b, //
        0, 0, 0, 1, 0,
      ];
    }
    return [
      c, 0, 0, 0, b, //
      0, c, 0, 0, b, //
      0, 0, c, 0, b, //
      0, 0, 0, 1, 0,
    ];
  }

  // ── Кадрирование (встроенное, без внешнего экрана) ──

  /// Применяет операцию пакета `image` к файлу базы и перезагружает превью.
  Future<void> _applyImageOp(img.Image Function(img.Image src) op) async {
    final bytes = await File(_basePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    final result = op(img.bakeOrientation(decoded));
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/pe_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(path).writeAsBytes(img.encodePng(result));
    if (!mounted) return;
    setState(() {
      _basePath = path;
      _cropRect = const Rect.fromLTRB(0, 0, 1, 1);
    });
    await _loadBase();
  }

  Future<void> _rotate90(int turns) async {
    _pushUndo();
    await _applyImageOp((s) => img.copyRotate(s, angle: 90.0 * turns));
  }

  Future<void> _applyCrop() async {
    if (_cropRect.left <= 0 &&
        _cropRect.top <= 0 &&
        _cropRect.right >= 1 &&
        _cropRect.bottom >= 1) {
      return; // нечего обрезать
    }
    final rect = _cropRect;
    _pushUndo();
    await _applyImageOp((s) {
      final l = (rect.left * s.width).round().clamp(0, s.width - 1);
      final t = (rect.top * s.height).round().clamp(0, s.height - 1);
      final cw = ((rect.width) * s.width).round().clamp(1, s.width - l);
      final ch = ((rect.height) * s.height).round().clamp(1, s.height - t);
      return img.copyCrop(s, x: l, y: t, width: cw, height: ch);
    });
  }

  _CropHandle? _hitHandle(Offset p, double dispW, double dispH) {
    final r = Rect.fromLTRB(
      _cropRect.left * dispW,
      _cropRect.top * dispH,
      _cropRect.right * dispW,
      _cropRect.bottom * dispH,
    );
    const tol = 34.0;
    if ((p - r.topLeft).distance < tol) return _CropHandle.tl;
    if ((p - r.topRight).distance < tol) return _CropHandle.tr;
    if ((p - r.bottomLeft).distance < tol) return _CropHandle.bl;
    if ((p - r.bottomRight).distance < tol) return _CropHandle.br;
    if (r.contains(p)) return _CropHandle.move;
    return null;
  }

  void _adjustCrop(double dnx, double dny) {
    const minSz = 0.12;
    var r = _cropRect;
    switch (_dragHandle) {
      case _CropHandle.tl:
        r = Rect.fromLTRB(
          (r.left + dnx).clamp(0.0, r.right - minSz),
          (r.top + dny).clamp(0.0, r.bottom - minSz),
          r.right,
          r.bottom,
        );
        break;
      case _CropHandle.tr:
        r = Rect.fromLTRB(
          r.left,
          (r.top + dny).clamp(0.0, r.bottom - minSz),
          (r.right + dnx).clamp(r.left + minSz, 1.0),
          r.bottom,
        );
        break;
      case _CropHandle.bl:
        r = Rect.fromLTRB(
          (r.left + dnx).clamp(0.0, r.right - minSz),
          r.top,
          r.right,
          (r.bottom + dny).clamp(r.top + minSz, 1.0),
        );
        break;
      case _CropHandle.br:
        r = Rect.fromLTRB(
          r.left,
          r.top,
          (r.right + dnx).clamp(r.left + minSz, 1.0),
          (r.bottom + dny).clamp(r.top + minSz, 1.0),
        );
        break;
      case _CropHandle.move:
        final l = (r.left + dnx).clamp(0.0, 1.0 - r.width);
        final t = (r.top + dny).clamp(0.0, 1.0 - r.height);
        r = Rect.fromLTWH(l, t, r.width, r.height);
        break;
      case null:
        return;
    }
    setState(() => _cropRect = r);
  }

  // ── Штамп ──
  void _addStamp() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _pushUndo();
    setState(() {
      _stamp = _Stamp(
        text:
            '${two(now.day)}.${two(now.month)}.${now.year}  '
            '${two(now.hour)}:${two(now.minute)}',
        fontFrac: 0.045,
        styleIndex: 0,
        color: Colors.white,
        backdrop: true,
        norm: const Offset(0.05, 0.86),
      );
    });
    _stampCtrl.text = _stamp!.text;
  }

  Future<void> _addStampLocation() async {
    if (_locating || _stamp == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);
    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        _toast(l10n.geoStampLocationDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      String loc = '';
      try {
        loc = _formatAddress(
          await placemarkFromCoordinates(pos.latitude, pos.longitude),
        );
      } catch (_) {}
      if (loc.isEmpty) {
        loc =
            '${pos.latitude.toStringAsFixed(5)}, '
            '${pos.longitude.toStringAsFixed(5)}';
      }
      if (!_stamp!.text.contains(loc)) {
        _pushUndo();
        setState(() => _stamp!.text = '${_stamp!.text}\n$loc');
        _stampCtrl.text = _stamp!.text;
      }
    } catch (_) {
      _toast(l10n.geoStampLocationDenied);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _formatAddress(List<Placemark> placemarks) {
    if (placemarks.isEmpty) return '';
    final pm = placemarks.first;
    String s(String? v) => (v ?? '').trim();
    final city = s(pm.locality).isNotEmpty
        ? s(pm.locality)
        : s(pm.subAdministrativeArea);
    final street = [
      s(pm.thoroughfare),
      s(pm.subThoroughfare),
    ].where((e) => e.isNotEmpty).join(' ');
    return [city, street].where((e) => e.isNotEmpty).join(', ');
  }

  // ── Подпись ──
  Future<void> _addSignature() async {
    final l10n = AppLocalizations.of(context);
    final controller = SignatureController(
      penStrokeWidth: 4,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
    final png = await showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2A3A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.peSignDraw,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Signature(
                controller: controller,
                height: 220,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => controller.clear(),
                    icon: const Icon(Icons.clear, size: 18),
                    label: Text(l10n.peSignClear),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final nav = Navigator.of(ctx);
                      if (controller.isEmpty) {
                        nav.pop();
                        return;
                      }
                      final bytes = await controller.toPngBytes();
                      nav.pop(bytes);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(l10n.peSignDone),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (png == null || !mounted) return;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    _pushUndo();
    setState(() {
      _sign = _Sign(
        png: png,
        image: frame.image,
        widthFrac: 0.4,
        norm: const Offset(0.3, 0.55),
      );
    });
  }

  // ── Сохранение (флэттен) ──
  Future<void> _save() async {
    final base = _base;
    if (base == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final w = base.width.toDouble();
      final h = base.height.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

      // База с цветовым фильтром.
      canvas.drawImage(
        base,
        Offset.zero,
        Paint()..colorFilter = ColorFilter.matrix(_colorMatrix()),
      );

      // Подпись.
      final sign = _sign;
      if (sign != null) {
        final sw = w * sign.widthFrac;
        final sh = sw * sign.image.height / sign.image.width;
        canvas.drawImageRect(
          sign.image,
          Rect.fromLTWH(
            0,
            0,
            sign.image.width.toDouble(),
            sign.image.height.toDouble(),
          ),
          Rect.fromLTWH(sign.norm.dx * w, sign.norm.dy * h, sw, sh),
          Paint(),
        );
      }

      // Штамп.
      final stamp = _stamp;
      if (stamp != null && stamp.text.trim().isNotEmpty) {
        final style = _styles(l10n)[stamp.styleIndex];
        final fontSize = stamp.fontFrac * w;
        final pb =
            ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  fontSize: fontSize,
                  fontFamily: style.family,
                  fontWeight: style.weight,
                  fontStyle: style.fontStyle,
                  textDirection: TextDirection.ltr,
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  color: stamp.color,
                  fontSize: fontSize,
                  fontFamily: style.family,
                  fontWeight: style.weight,
                  fontStyle: style.fontStyle,
                  background: stamp.backdrop
                      ? (Paint()..color = const Color(0xAA000000))
                      : null,
                ),
              )
              ..addText(stamp.text);
        final paragraph = pb.build()..layout(ui.ParagraphConstraints(width: w));
        canvas.drawParagraph(
          paragraph,
          Offset(stamp.norm.dx * w, stamp.norm.dy * h),
        );
      }

      final pic = recorder.endRecording();
      final out = await pic.toImage(base.width, base.height);
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('encode failed');

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'edited_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = '${dir.path}/$fileName';
      await File(destPath).writeAsBytes(bytes.buffer.asUint8List());

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList('saved_document_paths') ?? [];
      if (!paths.contains(destPath)) {
        paths.add(destPath);
        await prefs.setStringList('saved_document_paths', paths);
      }
      await DocumentRegistry().add(
        DocEntry(
          localPath: destPath,
          remoteId: null,
          name: p.basenameWithoutExtension(fileName),
        ),
      );
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(AppLocalizations.of(context).commonError);
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(l10n.peTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.undo,
            onPressed: _undo.isEmpty ? null : _doUndo,
          ),
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(
                    l10n.geoStampSave,
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
      body: _base == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: _previewBottomReserve(context),
                    ),
                    child: _buildPreview(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_tool != PhotoEditorTool.bw) _buildPanel(l10n),
                      _buildToolBar(l10n),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  double _previewBottomReserve(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 360;
    final toolbarHeight = (isCompact ? 82.0 : 90.0) + 14.0 + mq.padding.bottom;
    final panelHeight =
        widget.tools.length == 1 && widget.tools.first == PhotoEditorTool.bw
        ? 0.0
        : widget.tools.any(
            (tool) =>
                tool == PhotoEditorTool.stamp ||
                tool == PhotoEditorTool.signature,
          )
        ? 120.0
        : 96.0;
    return toolbarHeight + panelHeight;
  }

  Widget _buildPreview() {
    final base = _base!;
    return Center(
      child: AspectRatio(
        aspectRatio: base.width / base.height,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final dispW = c.maxWidth;
            final dispH = c.maxHeight;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: ColorFiltered(
                    colorFilter: ColorFilter.matrix(_colorMatrix()),
                    child: RawImage(image: base, fit: BoxFit.fill),
                  ),
                ),
                // В режиме обрезки — рамка с ручками поверх фото (без оверлеев).
                if (_tool == PhotoEditorTool.crop)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _dragHandle = _hitHandle(
                        d.localPosition,
                        dispW,
                        dispH,
                      ),
                      onPanUpdate: (d) {
                        if (_dragHandle == null) return;
                        _adjustCrop(d.delta.dx / dispW, d.delta.dy / dispH);
                      },
                      onPanEnd: (_) => _dragHandle = null,
                      child: CustomPaint(
                        painter: _CropPainter(_cropRect, _accent),
                        size: Size(dispW, dispH),
                      ),
                    ),
                  )
                else ...[
                  if (_sign != null) _buildSignOverlay(dispW, dispH),
                  if (_stamp != null) _buildStampOverlay(dispW, dispH),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSignOverlay(double dispW, double dispH) {
    final sign = _sign!;
    final w = dispW * sign.widthFrac;
    final h = w * sign.image.height / sign.image.width;
    return Positioned(
      left: sign.norm.dx * dispW,
      top: sign.norm.dy * dispH,
      width: w,
      height: h,
      child: GestureDetector(
        onPanStart: (_) => _pushUndo(),
        onPanUpdate: (d) => setState(() {
          sign.norm = Offset(
            (sign.norm.dx + d.delta.dx / dispW).clamp(0.0, 0.98),
            (sign.norm.dy + d.delta.dy / dispH).clamp(0.0, 0.98),
          );
        }),
        child: RawImage(image: sign.image, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildStampOverlay(double dispW, double dispH) {
    final stamp = _stamp!;
    final style = _styles(AppLocalizations.of(context))[stamp.styleIndex];
    return Positioned(
      left: stamp.norm.dx * dispW,
      top: stamp.norm.dy * dispH,
      child: GestureDetector(
        onPanStart: (_) => _pushUndo(),
        onPanUpdate: (d) => setState(() {
          stamp.norm = Offset(
            (stamp.norm.dx + d.delta.dx / dispW).clamp(0.0, 0.98),
            (stamp.norm.dy + d.delta.dy / dispH).clamp(0.0, 0.98),
          );
        }),
        child: Container(
          padding: stamp.backdrop
              ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
              : EdgeInsets.zero,
          decoration: stamp.backdrop
              ? BoxDecoration(
                  color: const Color(0xAA000000),
                  borderRadius: BorderRadius.circular(4),
                )
              : null,
          child: Text(
            stamp.text,
            style: TextStyle(
              color: stamp.color,
              fontSize: stamp.fontFrac * dispW,
              height: 1.2,
              fontFamily: style.family,
              fontWeight: style.weight,
              fontStyle: style.fontStyle,
              shadows: stamp.backdrop
                  ? null
                  : const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolBar(AppLocalizations l10n) {
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 360;
    final safeBottom = mq.padding.bottom;
    final tileWidth = isCompact ? 72.0 : 84.0;
    final fontSize = isCompact ? 10.5 : 11.5;
    final iconSize = isCompact ? 20.0 : 24.0;

    final items = <(PhotoEditorTool, IconData, String)>[
      (PhotoEditorTool.crop, Icons.crop, l10n.editToolCrop),
      (
        PhotoEditorTool.brightness,
        Icons.wb_sunny_outlined,
        l10n.colorBrightness,
      ),
      (PhotoEditorTool.contrast, Icons.contrast, l10n.colorContrast),
      (PhotoEditorTool.bw, Icons.filter_b_and_w, l10n.editToolBW),
      (PhotoEditorTool.stamp, Icons.punch_clock_outlined, l10n.peTabStamp),
      (PhotoEditorTool.signature, Icons.draw_outlined, l10n.featSignature),
    ]..removeWhere((it) => !widget.tools.contains(it.$1));
    return Container(
      color: const Color(0xFF101820),
      padding: EdgeInsets.fromLTRB(0, 6, 0, 8 + safeBottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth - 24;
          final fittedTileWidth = items.isEmpty
              ? tileWidth
              : available / items.length;
          final effectiveTileWidth = fittedTileWidth > tileWidth
              ? fittedTileWidth
              : tileWidth;
          return SizedBox(
            height: isCompact ? 82 : 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final it = items[index];
                return _toolButton(
                  icon: it.$2,
                  label: it.$3,
                  active: _isToolActive(it.$1),
                  tileWidth: effectiveTileWidth,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  isCompact: isCompact,
                  onTap: () => _selectTool(it.$1),
                );
              },
            ),
          );
        },
      ),
    );
  }

  bool _isToolActive(PhotoEditorTool tool) {
    if (tool == PhotoEditorTool.bw) return _grayscale;
    return _tool == tool;
  }

  void _selectTool(PhotoEditorTool tool) {
    if (tool == PhotoEditorTool.bw) {
      _pushUndo();
      setState(() {
        _tool = tool;
        _grayscale = !_grayscale;
      });
      return;
    }
    setState(() => _tool = tool);
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required double tileWidth,
    required double iconSize,
    required double fontSize,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: tileWidth,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 3 : 4),
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
                  color: active
                      ? _accent
                      : Colors.white.withValues(alpha: 0.14),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.55),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Icon(icon, color: Colors.white, size: iconSize),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: fontSize,
                      height: 1.15,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(AppLocalizations l10n) {
    final minHeight = switch (_tool) {
      PhotoEditorTool.crop => 96.0,
      PhotoEditorTool.brightness => 74.0,
      PhotoEditorTool.contrast => 74.0,
      PhotoEditorTool.bw => 0.0,
      PhotoEditorTool.stamp => 120.0,
      PhotoEditorTool.signature => 120.0,
    };
    return Container(
      color: const Color(0xFF0F1923),
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: switch (_tool) {
        PhotoEditorTool.crop => _cropPanel(l10n),
        PhotoEditorTool.brightness => _brightnessPanel(l10n),
        PhotoEditorTool.contrast => _contrastPanel(l10n),
        PhotoEditorTool.bw => const SizedBox.shrink(),
        PhotoEditorTool.stamp => _stampPanel(l10n),
        PhotoEditorTool.signature => _signPanel(l10n),
      },
    );
  }

  Widget _cropPanel(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _cropAction(
              Icons.rotate_left,
              l10n.peRotateLeft,
              () => _rotate90(-1),
            ),
            _cropAction(
              Icons.rotate_right,
              l10n.peRotateRight,
              () => _rotate90(1),
            ),
            _cropAction(
              Icons.crop_free,
              l10n.peCropReset,
              () => setState(() => _cropRect = const Rect.fromLTRB(0, 0, 1, 1)),
            ),
            _cropAction(Icons.check, l10n.wmApply, _applyCrop, active: true),
          ],
        ),
      ],
    );
  }

  Widget _cropAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? _accent : Colors.white.withValues(alpha: 0.08),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessPanel(AppLocalizations l10n) {
    return _adjustPanel(
      value: _brightness,
      min: -0.5,
      max: 0.5,
      resetLabel: l10n.peCropReset,
      onChangeStart: () => _pushUndo(),
      onChanged: (v) => setState(() => _brightness = v),
      onReset: () {
        if (_brightness == 0.0) return;
        _pushUndo();
        setState(() => _brightness = 0.0);
      },
    );
  }

  Widget _contrastPanel(AppLocalizations l10n) {
    return _adjustPanel(
      value: _contrast,
      min: 0.5,
      max: 2.0,
      resetLabel: l10n.peCropReset,
      onChangeStart: () => _pushUndo(),
      onChanged: (v) => setState(() => _contrast = v),
      onReset: () {
        if (_contrast == 1.0) return;
        _pushUndo();
        setState(() => _contrast = 1.0);
      },
    );
  }

  Widget _adjustPanel({
    required double value,
    required double min,
    required double max,
    required String resetLabel,
    required VoidCallback onChangeStart,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: _accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              thumbColor: _accent,
              overlayColor: _accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 9,
                elevation: 0,
                pressedElevation: 1,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChangeStart: (_) => onChangeStart(),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(resetLabel),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
    );
  }

  Widget _stampPanel(AppLocalizations l10n) {
    if (_stamp == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _addStamp,
          icon: const Icon(Icons.add),
          label: Text(l10n.peAddStamp),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    final stamp = _stamp!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _stampCtrl,
                onChanged: (v) => stamp.text = v,
                onSubmitted: (_) => setState(() {}),
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.geoStampText,
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: l10n.geoStampAddLocation,
              onPressed: _locating ? null : _addStampLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: _accent),
            ),
            IconButton(
              tooltip: l10n.peRemove,
              onPressed: () {
                _pushUndo();
                setState(() => _stamp = null);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              l10n.geoStampSize,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Expanded(
              child: Slider(
                value: stamp.fontFrac,
                min: 0.02,
                max: 0.1,
                onChangeStart: (_) => _pushUndo(),
                onChanged: (v) => setState(() => stamp.fontFrac = v),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _styles(l10n).length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_styles(l10n)[i].label),
                    selected: stamp.styleIndex == i,
                    onSelected: (_) {
                      _pushUndo();
                      setState(() => stamp.styleIndex = i);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in _stampColors)
              GestureDetector(
                onTap: () {
                  _pushUndo();
                  setState(() => stamp.color = c);
                },
                child: Container(
                  width: 26,
                  height: 26,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: stamp.color == c ? _accent : Colors.white24,
                      width: stamp.color == c ? 3 : 1,
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Text(
              l10n.geoStampBackground,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Switch(
              value: stamp.backdrop,
              onChanged: (v) {
                _pushUndo();
                setState(() => stamp.backdrop = v);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _signPanel(AppLocalizations l10n) {
    if (_sign == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _addSignature,
          icon: const Icon(Icons.draw),
          label: Text(l10n.peAddSignature),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    final sign = _sign!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              l10n.geoStampSize,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Expanded(
              child: Slider(
                value: sign.widthFrac,
                min: 0.15,
                max: 0.8,
                onChangeStart: (_) => _pushUndo(),
                onChanged: (v) => setState(() => sign.widthFrac = v),
              ),
            ),
            IconButton(
              tooltip: l10n.peRemove,
              onPressed: () {
                _pushUndo();
                setState(() => _sign = null);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.white54),
            ),
          ],
        ),
      ],
    );
  }
}

/// Рисует рамку обрезки: затемнение снаружи, границу с сеткой и угловые ручки.
class _CropPainter extends CustomPainter {
  final Rect rect; // нормализованный (0..1)
  final Color accent;
  const _CropPainter(this.rect, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Затемнение всего, кроме рамки.
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(r),
    );
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );

    // Граница.
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // Сетка «правило третей».
    // Угловые ручки.
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = r.left + r.width * i / 3;
      final y = r.top + r.height * i / 3;
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }

    final handle = Paint()..color = accent;
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 8, handle);
      canvas.drawCircle(
        c,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect != rect || old.accent != accent;
}
