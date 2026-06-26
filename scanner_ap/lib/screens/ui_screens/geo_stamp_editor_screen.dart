import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/document_registry.dart';

enum _GeoStampTool { text, location, size, style, color, backdrop }

class _StampStyle {
  final String label;
  final String? family;
  final FontWeight weight;
  final bool italic;

  const _StampStyle(this.label, this.family, this.weight, this.italic);

  FontStyle get fontStyle => italic ? FontStyle.italic : FontStyle.normal;
}

class GeoStampEditorScreen extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onSaved;

  const GeoStampEditorScreen({
    super.key,
    required this.imagePath,
    this.onSaved,
  });

  @override
  State<GeoStampEditorScreen> createState() => _GeoStampEditorScreenState();
}

class _GeoStampEditorScreenState extends State<GeoStampEditorScreen> {
  static const _accent = Color(0xFF2CA5E0);
  static const _documentKey = 'saved_document_paths';
  static const _colors = [
    Colors.white,
    Colors.black,
    Color(0xFFFFEB3B),
    _accent,
    Color(0xFFFF5252),
  ];

  ui.Image? _img;
  late final TextEditingController _textCtrl;

  Offset _norm = const Offset(0.05, 0.86);
  double _fontFrac = 0.045;
  int _styleIndex = 0;
  Color _color = Colors.white;
  bool _backdrop = true;
  bool _saving = false;
  bool _locating = false;
  bool _draggingStamp = false;
  _GeoStampTool _tool = _GeoStampTool.text;

  List<_StampStyle> _styles(AppLocalizations l10n) => [
    _StampStyle(l10n.geoStyleNormal, null, FontWeight.w500, false),
    _StampStyle(l10n.geoStyleBold, null, FontWeight.w800, false),
    _StampStyle(l10n.geoStyleItalic, null, FontWeight.w500, true),
    _StampStyle(l10n.geoStyleSerif, 'serif', FontWeight.w600, false),
    _StampStyle(l10n.geoStyleMono, 'monospace', FontWeight.w600, false),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _textCtrl = TextEditingController(
      text:
          '${two(now.day)}.${two(now.month)}.${now.year}  '
          '${two(now.hour)}:${two(now.minute)}',
    );
    _loadImage();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _img?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _img = frame.image);
  }

  Future<void> _addLocation() async {
    if (_locating) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _locating = true);
    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        _toast(l10n.geoStampLocationDenied);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      var loc = '';
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

      if (!_textCtrl.text.contains(loc)) {
        _textCtrl.text = '${_textCtrl.text}\n$loc';
        if (mounted) setState(() {});
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
    final streetLine = [
      s(pm.thoroughfare),
      s(pm.subThoroughfare),
    ].where((e) => e.isNotEmpty).join(' ');
    return [city, streetLine].where((e) => e.isNotEmpty).join(', ');
  }

  ui.Paragraph _buildParagraph(
    _StampStyle style,
    double fontSize,
    double maxWidth,
  ) {
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
              color: _color,
              fontSize: fontSize,
              fontFamily: style.family,
              fontWeight: style.weight,
              fontStyle: style.fontStyle,
              background: _backdrop
                  ? (Paint()..color = const Color(0xAA000000))
                  : null,
            ),
          )
          ..addText(_textCtrl.text);
    return pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  Future<void> _save() async {
    final image = _img;
    if (image == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final style = _styles(l10n)[_styleIndex];
    setState(() => _saving = true);
    try {
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
      canvas.drawImage(image, Offset.zero, Paint());
      canvas.drawParagraph(
        _buildParagraph(style, _fontFrac * w, w),
        Offset(_norm.dx * w, _norm.dy * h),
      );

      final picture = recorder.endRecording();
      final out = await picture.toImage(image.width, image.height);
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('encode failed');

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'stamped_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = '${dir.path}/$fileName';
      await File(destPath).writeAsBytes(bytes.buffer.asUint8List());

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(destPath)) {
        paths.add(destPath);
        await prefs.setStringList(_documentKey, paths);
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
    final style = _styles(l10n)[_styleIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          l10n.featGeoStamp,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
        ),
        flexibleSpace: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(18),
          ),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: const Color(0xFF05090D).withValues(alpha: 0.58),
            ),
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
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
          else
            TextButton(
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
      body: _img == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Stack(
              children: [
                Positioned.fill(child: _buildPreview(style)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasActivePanel) _buildActivePanel(l10n),
                      _buildToolBar(l10n),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  bool get _hasActivePanel =>
      _tool == _GeoStampTool.text ||
      _tool == _GeoStampTool.size ||
      _tool == _GeoStampTool.style ||
      _tool == _GeoStampTool.color;

  Widget _buildPreview(_StampStyle style) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final box = Size(c.maxWidth, c.maxHeight);
        final bottomOverlayHeight = _bottomOverlayHeight(ctx);
        final display = _displayRect(box, bottomOverlayHeight);
        final stampNorm = _clampToImage(_norm);
        if ((stampNorm - _norm).distance > 0.001) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _norm = stampNorm);
          });
        }
        final contentHeight = math.max(
          box.height,
          display.bottom + bottomOverlayHeight,
        );
        final displayFontSize = _fontFrac * display.width;
        const hitSlop = 24.0;
        return SingleChildScrollView(
          physics: _draggingStamp
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
          child: SizedBox(
            width: box.width,
            height: contentHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fromRect(
                  rect: display,
                  child: RawImage(image: _img!, fit: BoxFit.fill),
                ),
                Positioned(
                  left: display.left + stampNorm.dx * display.width - hitSlop,
                  top: display.top + stampNorm.dy * display.height - hitSlop,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (!_draggingStamp) {
                        setState(() => _draggingStamp = true);
                      }
                    },
                    onPointerMove: (event) {
                      setState(() {
                        _norm = _clampToImage(
                          Offset(
                            _norm.dx + event.delta.dx / display.width,
                            _norm.dy + event.delta.dy / display.height,
                          ),
                        );
                      });
                    },
                    onPointerUp: (_) {
                      if (_draggingStamp) {
                        setState(() => _draggingStamp = false);
                      }
                    },
                    onPointerCancel: (_) {
                      if (_draggingStamp) {
                        setState(() => _draggingStamp = false);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(hitSlop),
                      child: _stampWidget(style, displayFontSize),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Rect _displayRect(Size box, double bottomOverlayHeight) {
    final image = _img!;
    final scale = box.width / image.width;
    final w = image.width * scale;
    final h = image.height * scale;
    final visibleHeight = math.max(0.0, box.height - bottomOverlayHeight);
    final top = h <= visibleHeight ? (visibleHeight - h) / 2 : 0.0;
    return Rect.fromLTWH((box.width - w) / 2, top, w, h);
  }

  double _bottomOverlayHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isCompact = mq.size.width < 360;
    final toolbarHeight = (isCompact ? 82.0 : 90.0) + 14 + mq.padding.bottom;
    return toolbarHeight + (_hasActivePanel ? 96.0 : 0.0);
  }

  Offset _clampToImage(Offset value) {
    return Offset(
      value.dx.clamp(0.0, 0.98).toDouble(),
      value.dy.clamp(0.0, 0.98).toDouble(),
    );
  }

  Widget _stampWidget(_StampStyle style, double fontSize) {
    return Container(
      padding: _backdrop
          ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
          : EdgeInsets.zero,
      decoration: _backdrop
          ? BoxDecoration(
              color: const Color(0xAA000000),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Text(
        _textCtrl.text,
        style: TextStyle(
          color: _color,
          fontSize: fontSize,
          height: 1.2,
          fontFamily: style.family,
          fontWeight: style.weight,
          fontStyle: style.fontStyle,
          shadows: _backdrop
              ? null
              : const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
    );
  }

  Widget _buildActivePanel(AppLocalizations l10n) {
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: const Color(0xFF0F1923).withValues(alpha: 0.58),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: switch (_tool) {
            _GeoStampTool.text => _textPanel(l10n),
            _GeoStampTool.size => _sizePanel(l10n),
            _GeoStampTool.style => _stylePanel(l10n),
            _GeoStampTool.color => _colorPanel(),
            _GeoStampTool.location => const SizedBox.shrink(),
            _GeoStampTool.backdrop => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _textPanel(AppLocalizations l10n) {
    return TextField(
      controller: _textCtrl,
      onChanged: (_) => setState(() {}),
      maxLines: 2,
      minLines: 1,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: l10n.geoStampText,
        labelStyle: const TextStyle(color: Colors.white54),
        isDense: true,
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _accent),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _sizePanel(AppLocalizations l10n) {
    return Row(
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
              value: _fontFrac,
              min: 0.02,
              max: 0.10,
              onChanged: (v) => setState(() => _fontFrac = v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => setState(() => _fontFrac = 0.045),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: Text(l10n.peCropReset),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      ],
    );
  }

  Widget _stylePanel(AppLocalizations l10n) {
    final styles = _styles(l10n);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < styles.length; i++) ...[
            _choicePill(
              label: styles[i].label,
              selected: _styleIndex == i,
              onTap: () => setState(() => _styleIndex = i),
            ),
            if (i != styles.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _choicePill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _accent : Colors.white54,
            width: 1.3,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _colorPanel() {
    return Center(
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final c in _colors)
            GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == c ? _accent : Colors.white24,
                    width: _color == c ? 3 : 1,
                  ),
                  boxShadow: _color == c
                      ? [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
        ],
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
    final items = <(_GeoStampTool, IconData, String)>[
      (_GeoStampTool.text, Icons.text_fields, l10n.geoStampText),
      (_GeoStampTool.location, Icons.my_location, l10n.geoStampAddLocation),
      (_GeoStampTool.size, Icons.format_size, l10n.geoStampSize),
      (_GeoStampTool.style, Icons.format_bold, l10n.geoStampStyle),
      (_GeoStampTool.color, Icons.palette_outlined, l10n.geoStampColor),
      (_GeoStampTool.backdrop, Icons.layers, l10n.geoStampBackground),
    ];

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          color: const Color(0xFF101820).withValues(alpha: 0.62),
          padding: EdgeInsets.fromLTRB(0, 6, 0, 8 + safeBottom),
          child: SizedBox(
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
                  busy: it.$1 == _GeoStampTool.location && _locating,
                  tileWidth: tileWidth,
                  iconSize: iconSize,
                  fontSize: fontSize,
                  isCompact: isCompact,
                  onTap: () => _selectTool(it.$1),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _isToolActive(_GeoStampTool tool) {
    return switch (tool) {
      _GeoStampTool.location => _locating || _textCtrl.text.contains('\n'),
      _GeoStampTool.backdrop => _backdrop,
      _ => _tool == tool,
    };
  }

  void _selectTool(_GeoStampTool tool) {
    if (tool == _GeoStampTool.location) {
      setState(() => _tool = tool);
      _addLocation();
      return;
    }
    if (tool == _GeoStampTool.backdrop) {
      setState(() {
        _tool = tool;
        _backdrop = !_backdrop;
      });
      return;
    }
    setState(() => _tool = tool);
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required bool active,
    required bool busy,
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
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(icon, color: Colors.white, size: iconSize),
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
}
