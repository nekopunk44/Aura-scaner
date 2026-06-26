import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';

/// «Горячая зона»: наводишь камеру, тапаешь по подписи/тексту/визитке —
/// распознаётся область вокруг тапа и из неё собирается карточка контакта.
///
/// OCR — Tesseract `rus+eng` (кириллица + латиница). Координаты тапа
/// переводятся в пиксели снимка через cover-преобразование, а сам снимок
/// доворачивается по EXIF (`bakeOrientation`), чтобы вырез совпадал с местом
/// тапа независимо от ориентации сенсора.
class HotZoneScreen extends StatefulWidget {
  const HotZoneScreen({super.key});

  @override
  State<HotZoneScreen> createState() => _HotZoneScreenState();
}

enum _CamState { loading, ready, denied, error }

class _HotZoneScreenState extends State<HotZoneScreen> {
  // Доля кадра, попадающая в «горячую зону» вокруг тапа (широкая и низкая —
  // под строку текста / подпись).
  static const double _fracW = 0.72;
  static const double _fracH = 0.24;
  static const _accent = Color(0xFF2CA5E0);

  CameraController? _camCtrl;
  _CamState _state = _CamState.loading;
  bool _processing = false;
  Offset? _tapPos;
  // Рамка-результат в экранных координатах — обтягивает реально найденный текст.
  Rect? _resultRect;
  _ContactCard? _card;

  // Зум (pinch).
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _camCtrl?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (mounted) setState(() => _state = _CamState.loading);
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) setState(() => _state = _CamState.denied);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _state = _CamState.error);
        return;
      }
      final ctrl = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _minZoom = await ctrl.getMinZoomLevel();
      _maxZoom = await ctrl.getMaxZoomLevel();
      _zoom = _minZoom;
      setState(() {
        _camCtrl = ctrl;
        _state = _CamState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _CamState.error);
    }
  }

  Future<void> _captureAndAnalyze(Offset tap, BoxConstraints constraints) async {
    if (_processing || _camCtrl == null || _state != _CamState.ready) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _processing = true;
      _card = null;
      _resultRect = null;
      _tapPos = tap;
    });

    String? tmpPath;
    try {
      final xFile = await _camCtrl!.takePicture();
      final bytes = await File(xFile.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('decode failed');
      // Доворачиваем по EXIF — снимок становится «как превью» (портрет).
      final up = img.bakeOrientation(decoded);
      final uW = up.width.toDouble();
      final uH = up.height.toDouble();

      // Cover-преобразование: бокс превью ↔ пиксели снимка (то же, как на экране).
      final bW = constraints.maxWidth;
      final bH = constraints.maxHeight;
      final s = math.max(bW / uW, bH / uH);
      final dx = (bW - uW * s) / 2;
      final dy = (bH - uH * s) / 2;
      final imgX = (tap.dx - dx) / s;
      final imgY = (tap.dy - dy) / s;

      final cropW = (uW * _fracW).round();
      final cropH = (uH * _fracH).round();
      final cropX = (imgX - cropW / 2).round().clamp(0, up.width - cropW);
      final cropY = (imgY - cropH / 2).round().clamp(0, up.height - cropH);

      var crop = img.copyCrop(up,
          x: cropX, y: cropY, width: cropW, height: cropH);
      // Мелкий вырез → апскейл для точности; коэффициент учтём в обратном маппинге.
      double ocrScale = 1.0;
      if (crop.width < 1000) {
        final resized = img.copyResize(crop, width: 1000);
        ocrScale = resized.width / crop.width;
        crop = resized;
      }

      final dir = await getApplicationDocumentsDirectory();
      tmpPath =
          '${dir.path}/hotzone_crop_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tmpPath).writeAsBytes(img.encodePng(crop));

      // hOCR даёт и текст, и рамки слов — обводка обтянет реальный текст.
      final hocr = await FlutterTesseractOcr.extractHocr(
        tmpPath,
        language: 'rus+eng',
      );
      final words = _parseHocrWords(hocr);

      if (!mounted) return;
      if (words.isEmpty) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.hotZoneNoText)),
        );
        return;
      }

      // Union рамок слов (в пикселях выреза) → снимок → экран.
      final union = _wordsUnion(words);
      final imgL = cropX + union.left / ocrScale;
      final imgT = cropY + union.top / ocrScale;
      final imgR = cropX + union.right / ocrScale;
      final imgB = cropY + union.bottom / ocrScale;
      const pad = 6.0;
      final rect = Rect.fromLTRB(
        dx + imgL * s - pad,
        dy + imgT * s - pad,
        dx + imgR * s + pad,
        dy + imgB * s + pad,
      );

      setState(() {
        _card = _parseContact(_wordsToText(words));
        _resultRect = rect;
        _processing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.commonError}: $e')),
        );
      }
    } finally {
      if (tmpPath != null) {
        try {
          await File(tmpPath).delete();
        } catch (_) {}
      }
    }
  }

  // hOCR-слова: рамка (bbox в пикселях выреза) + текст.
  List<_Word> _parseHocrWords(String hocr) {
    final re = RegExp(
      r'''class=['"]ocrx_word['"][^>]*?title=['"]bbox (\d+) (\d+) (\d+) (\d+)[^'"]*['"][^>]*>(.*?)</span>''',
      dotAll: true,
    );
    final words = <_Word>[];
    for (final m in re.allMatches(hocr)) {
      final text = _stripTags(m.group(5)!).trim();
      if (text.isEmpty) continue;
      words.add(_Word(
        double.parse(m.group(1)!),
        double.parse(m.group(2)!),
        double.parse(m.group(3)!),
        double.parse(m.group(4)!),
        text,
      ));
    }
    return words;
  }

  String _stripTags(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  Rect _wordsUnion(List<_Word> words) {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final w in words) {
      l = math.min(l, w.x0);
      t = math.min(t, w.y0);
      r = math.max(r, w.x1);
      b = math.max(b, w.y1);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  // Слова → текст с восстановлением строк (группировка по вертикали).
  String _wordsToText(List<_Word> words) {
    if (words.isEmpty) return '';
    final avgH =
        words.map((w) => w.y1 - w.y0).reduce((a, b) => a + b) / words.length;
    final sorted = [...words]..sort((a, b) => a.y0.compareTo(b.y0));
    final lines = <List<_Word>>[];
    for (final w in sorted) {
      if (lines.isEmpty) {
        lines.add([w]);
        continue;
      }
      final last = lines.last;
      final lastY =
          last.map((e) => e.y0).reduce((a, b) => a + b) / last.length;
      if ((w.y0 - lastY).abs() <= avgH * 0.6) {
        last.add(w);
      } else {
        lines.add([w]);
      }
    }
    return lines.map((ln) {
      ln.sort((a, b) => a.x0.compareTo(b.x0));
      return ln.map((e) => e.text).join(' ');
    }).join('\n');
  }

  _ContactCard _parseContact(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final phoneRe = RegExp(r'[\+\(]?[\d][\d\s\-\(\)]{6,}');
    final emailRe = RegExp(r'[\w\.\-]+@[\w\.\-]+\.\w{2,}');
    final urlRe = RegExp(r'(https?://|www\.)\S+');

    String? name;
    String? phone;
    String? email;
    String? url;
    final others = <String>[];

    for (final line in lines) {
      if (email == null && emailRe.hasMatch(line)) {
        email = emailRe.firstMatch(line)!.group(0);
      } else if (phone == null && phoneRe.hasMatch(line)) {
        phone = phoneRe.firstMatch(line)!.group(0)?.trim();
      } else if (url == null && urlRe.hasMatch(line)) {
        url = urlRe.firstMatch(line)!.group(0);
      } else if (name == null &&
          line.length > 2 &&
          line.length < 50 &&
          !line.contains(RegExp(r'\d{3}'))) {
        name = line;
      } else if (line.length < 80) {
        others.add(line);
      }
    }

    return _ContactCard(
      rawText: rawText,
      name: name,
      phone: phone,
      email: email,
      url: url,
      extras: others.take(3).toList(),
    );
  }

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _launchPhone(String phone) =>
      _launch(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}'));

  void _launchEmail(String email) => _launch(Uri.parse('mailto:$email'));

  void _launchUrl(String url) {
    final normalized = url.startsWith('http') ? url : 'https://$url';
    _launch(Uri.parse(normalized));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.hotZoneTitle,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: switch (_state) {
        _CamState.loading => const Center(
            child: CircularProgressIndicator(color: _accent),
          ),
        _CamState.denied => _message(
            l10n,
            Icons.no_photography_outlined,
            l10n.hotZonePermission,
            actionLabel: l10n.hotZoneOpenSettings,
            onAction: () => openAppSettings(),
          ),
        _CamState.error => _message(
            l10n,
            Icons.error_outline,
            l10n.hotZoneCameraError,
            actionLabel: l10n.actionRetry,
            onAction: _initCamera,
          ),
        _CamState.ready => _buildCamera(l10n, isDark, textColor),
      },
    );
  }

  Widget _buildCamera(AppLocalizations l10n, bool isDark, Color textColor) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final ctrl = _camCtrl!;
      var scale = (constraints.maxWidth / constraints.maxHeight) *
          ctrl.value.aspectRatio;
      if (scale < 1) scale = 1 / scale;

      return Stack(
        children: [
          // Превью «cover» во весь экран (то же преобразование в мэппинге тапа).
          Positioned.fill(
            child: ClipRect(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: Center(child: CameraPreview(ctrl)),
              ),
            ),
          ),

          // Слой жестов: тап = снимок (onTapUp, чтобы пинч не срабатывал),
          // щипок двумя пальцами = зум.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _captureAndAnalyze(d.localPosition, constraints),
              onScaleStart: (_) => _baseZoom = _zoom,
              onScaleUpdate: (d) {
                if (d.pointerCount < 2) return;
                final z = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
                if ((z - _zoom).abs() < 0.01) return;
                _zoom = z;
                _camCtrl?.setZoomLevel(z);
                setState(() {});
              },
            ),
          ),

          // Во время сканирования — статичная рамка у тапа; после — рамка,
          // обтягивающая реально распознанный текст.
          if (_processing && _tapPos != null) _buildScanBox(constraints),
          if (!_processing && _resultRect != null) _buildResultBox(),

          // Индикатор зума.
          if (_zoom > _minZoom + 0.05)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('${_zoom.toStringAsFixed(1)}x',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),

          // Подсказка.
          if (!_processing && _card == null)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.hotZoneTapHint,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),

          if (_processing)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: _accent),
                      const SizedBox(height: 16),
                      Text(l10n.hotZoneProcessing,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),

          if (_card != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: _buildContactCard(_card!, isDark, textColor, l10n),
            ),
        ],
      );
    });
  }

  // Статичная рамка-«сканер» у тапа (показывается, пока идёт распознавание).
  Widget _buildScanBox(BoxConstraints constraints) {
    final w = constraints.maxWidth * _fracW;
    final h = constraints.maxHeight * _fracH;
    final left = (_tapPos!.dx - w / 2).clamp(0.0, constraints.maxWidth - w);
    final top = (_tapPos!.dy - h / 2).clamp(0.0, constraints.maxHeight - h);
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.amber, width: 2.5),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
    );
  }

  // Рамка по реально найденному тексту (обтягивает union слов).
  Widget _buildResultBox() {
    final r = _resultRect!;
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _accent, width: 2.5),
            borderRadius: BorderRadius.circular(8),
            color: _accent.withValues(alpha: 0.10),
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(_ContactCard card, bool isDark, Color textColor,
      AppLocalizations l10n) {
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2CA5E0), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.name ?? l10n.hotZoneContact,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                      if (card.extras.isNotEmpty)
                        Text(card.extras.first,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => setState(() {
                    _card = null;
                    _tapPos = null;
                    _resultRect = null;
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              children: [
                if (card.phone != null)
                  _cardRow(Icons.phone, card.phone!, isDark,
                      onTap: () => _launchPhone(card.phone!)),
                if (card.email != null)
                  _cardRow(Icons.email_outlined, card.email!, isDark,
                      onTap: () => _launchEmail(card.email!)),
                if (card.url != null)
                  _cardRow(Icons.link, card.url!, isDark,
                      onTap: () => _launchUrl(card.url!)),
                if (card.phone == null &&
                    card.email == null &&
                    card.url == null &&
                    card.rawText.isNotEmpty)
                  _cardRow(
                      Icons.text_fields,
                      card.rawText.length > 120
                          ? '${card.rawText.substring(0, 120)}…'
                          : card.rawText,
                      isDark),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.hotZoneScanAgain),
                onPressed: () => setState(() {
                  _card = null;
                  _tapPos = null;
                  _resultRect = null;
                }),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardRow(IconData icon, String text, bool isDark,
      {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : const Color(0xFF333D4B),
                  height: 1.4,
                )),
          ),
          if (onTap != null)
            const Icon(Icons.open_in_new, size: 15, color: _accent),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }

  Widget _message(
    AppLocalizations l10n,
    IconData icon,
    String text, {
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _accent),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, height: 1.4)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _Word {
  final double x0, y0, x1, y1;
  final String text;
  const _Word(this.x0, this.y0, this.x1, this.y1, this.text);
}

class _ContactCard {
  final String rawText;
  final String? name;
  final String? phone;
  final String? email;
  final String? url;
  final List<String> extras;

  _ContactCard({
    required this.rawText,
    this.name,
    this.phone,
    this.email,
    this.url,
    this.extras = const [],
  });
}
