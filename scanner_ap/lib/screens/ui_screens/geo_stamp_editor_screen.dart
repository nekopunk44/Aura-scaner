import 'dart:io';
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

/// Стиль начертания метки (семейство + насыщенность + курсив).
class _StampStyle {
  final String label;
  final String? family;
  final FontWeight weight;
  final bool italic;
  const _StampStyle(this.label, this.family, this.weight, this.italic);

  FontStyle get fontStyle => italic ? FontStyle.italic : FontStyle.normal;
}

/// Редактор метки «Местоположение и время»: метку можно **перетаскивать**,
/// менять **размер шрифта**, **стиль начертания**, цвет и подложку, а также
/// добавить **геолокацию**. Результат «впекается» в изображение и сохраняется.
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
  static const _documentKey = 'saved_document_paths';

  ui.Image? _img;
  late final TextEditingController _textCtrl;

  // Нормализованная позиция (0..1) левого-верхнего угла метки.
  Offset _norm = const Offset(0.05, 0.86);
  // Размер шрифта как доля ширины изображения.
  double _fontFrac = 0.045;
  int _styleIndex = 0;
  Color _color = Colors.white;
  bool _backdrop = true;
  bool _saving = false;
  bool _locating = false;

  List<_StampStyle> _styles(AppLocalizations l10n) => [
        _StampStyle(l10n.geoStyleNormal, null, FontWeight.w500, false),
        _StampStyle(l10n.geoStyleBold, null, FontWeight.w800, false),
        _StampStyle(l10n.geoStyleItalic, null, FontWeight.w500, true),
        _StampStyle(l10n.geoStyleSerif, 'serif', FontWeight.w600, false),
        _StampStyle(l10n.geoStyleMono, 'monospace', FontWeight.w600, false),
      ];

  static const _colors = [
    Colors.white,
    Colors.black,
    Color(0xFFFFEB3B), // жёлтый
    Color(0xFF2CA5E0), // синий
    Color(0xFFFF5252), // красный
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _textCtrl = TextEditingController(
      text: '${two(now.day)}.${two(now.month)}.${now.year}  '
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.geoStampLocationDenied)),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();

      // Реверс-геокодинг: человекочитаемый адрес вместо сырых координат.
      String loc = '';
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        loc = _formatAddress(placemarks);
      } catch (_) {
        // Нет сети/результата — откатимся на координаты ниже.
      }
      if (loc.isEmpty) {
        loc = '${pos.latitude.toStringAsFixed(5)}, '
            '${pos.longitude.toStringAsFixed(5)}';
      }

      final text = _textCtrl.text.contains(loc)
          ? _textCtrl.text
          : '${_textCtrl.text}\n$loc';
      _textCtrl.text = text;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.geoStampLocationDenied)),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Собирает компактный адрес из плейсмарка: «Город, Улица Дом».
  String _formatAddress(List<Placemark> placemarks) {
    if (placemarks.isEmpty) return '';
    final pm = placemarks.first;
    String s(String? v) => (v ?? '').trim();

    final city = s(pm.locality).isNotEmpty
        ? s(pm.locality)
        : s(pm.subAdministrativeArea);
    final streetLine = [s(pm.thoroughfare), s(pm.subThoroughfare)]
        .where((e) => e.isNotEmpty)
        .join(' ');
    final parts =
        [city, streetLine].where((e) => e.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  ui.Paragraph _buildParagraph(_StampStyle style, double fontSize, double maxWidth) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: fontSize,
      fontFamily: style.family,
      fontWeight: style.weight,
      fontStyle: style.fontStyle,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: _color,
        fontSize: fontSize,
        fontFamily: style.family,
        fontWeight: style.weight,
        fontStyle: style.fontStyle,
        background: _backdrop
            ? (Paint()..color = const Color(0xAA000000))
            : null,
      ))
      ..addText(_textCtrl.text);
    return pb.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  Future<void> _save() async {
    final img = _img;
    if (img == null || _saving) return;
    final l10n = AppLocalizations.of(context);
    final style = _styles(l10n)[_styleIndex];
    setState(() => _saving = true);
    try {
      final w = img.width.toDouble();
      final h = img.height.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
      canvas.drawImage(img, Offset.zero, Paint());

      final fontSize = _fontFrac * w;
      final paragraph = _buildParagraph(style, fontSize, w);
      canvas.drawParagraph(paragraph, Offset(_norm.dx * w, _norm.dy * h));

      final picture = recorder.endRecording();
      final out = await picture.toImage(img.width, img.height);
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
      await DocumentRegistry().add(DocEntry(
        localPath: destPath,
        remoteId: null,
        name: p.basenameWithoutExtension(fileName),
      ));
      widget.onSaved?.call();

      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).commonError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final style = _styles(l10n)[_styleIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.featGeoStamp,
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(l10n.geoStampSave,
                  style: const TextStyle(
                      color: Color(0xFF2CA5E0), fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: _img == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0)))
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _img!.width / _img!.height,
                      child: LayoutBuilder(builder: (ctx, c) {
                        final dispW = c.maxWidth;
                        final dispH = c.maxHeight;
                        return Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: RawImage(image: _img, fit: BoxFit.fill),
                            ),
                            Positioned(
                              left: _norm.dx * dispW,
                              top: _norm.dy * dispH,
                              child: GestureDetector(
                                onPanUpdate: (d) {
                                  setState(() {
                                    _norm = Offset(
                                      (_norm.dx + d.delta.dx / dispW)
                                          .clamp(0.0, 0.98),
                                      (_norm.dy + d.delta.dy / dispH)
                                          .clamp(0.0, 0.98),
                                    );
                                  });
                                },
                                child: _stampWidget(style, _fontFrac * dispW),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                _buildPanel(l10n, panelBg, textColor),
              ],
            ),
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

  Widget _buildPanel(AppLocalizations l10n, Color bg, Color textColor) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.open_with, size: 16, color: Color(0xFF8A97A8)),
                  const SizedBox(width: 6),
                  Text(l10n.geoStampHint,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A97A8))),
                ],
              ),
              const SizedBox(height: 10),

              // Текст метки + кнопка геолокации.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      onChanged: (_) => setState(() {}),
                      maxLines: 2,
                      minLines: 1,
                      style: TextStyle(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: l10n.geoStampText,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _addLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 16),
                    label: Text(l10n.geoStampAddLocation),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2CA5E0),
                      side: const BorderSide(color: Color(0xFF2CA5E0)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Размер шрифта.
              Row(
                children: [
                  Text(l10n.geoStampSize,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  Expanded(
                    child: Slider(
                      value: _fontFrac,
                      min: 0.02,
                      max: 0.10,
                      onChanged: (v) => setState(() => _fontFrac = v),
                    ),
                  ),
                ],
              ),

              // Стиль начертания.
              Text(l10n.geoStampStyle,
                  style: TextStyle(fontSize: 13, color: textColor)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _styles(l10n).length; i++)
                    ChoiceChip(
                      label: Text(_styles(l10n)[i].label),
                      selected: _styleIndex == i,
                      onSelected: (_) => setState(() => _styleIndex = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Цвет + подложка.
              Row(
                children: [
                  Text(l10n.geoStampColor,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  const SizedBox(width: 12),
                  for (final c in _colors) ...[
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 28, height: 28,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == c
                                ? const Color(0xFF2CA5E0)
                                : Colors.white24,
                            width: _color == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(l10n.geoStampBackground,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  Switch(
                    value: _backdrop,
                    onChanged: (v) => setState(() => _backdrop = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
