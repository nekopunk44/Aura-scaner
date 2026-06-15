import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import '../../l10n/app_localizations.dart';

class HotZoneScreen extends StatefulWidget {
  const HotZoneScreen({super.key});

  @override
  State<HotZoneScreen> createState() => _HotZoneScreenState();
}

class _HotZoneScreenState extends State<HotZoneScreen> {
  CameraController? _camCtrl;
  bool _cameraReady = false;
  bool _processing = false;
  _ContactCard? _card;

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
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    final ctrl = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await ctrl.initialize();
    if (!mounted) return;
    _camCtrl = ctrl;
    setState(() => _cameraReady = true);
  }

  Future<void> _captureAndAnalyze(TapDownDetails details, BoxConstraints constraints) async {
    if (_processing || _camCtrl == null || !_cameraReady) return;
    setState(() { _processing = true; _card = null; });
    final l10n = AppLocalizations.of(context);

    try {
      final xFile = await _camCtrl!.takePicture();
      final imageBytes = await File(xFile.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final fullImage = frame.image;

      final tapX = details.localPosition.dx / constraints.maxWidth;
      final tapY = details.localPosition.dy / constraints.maxHeight;

      final cropW = (fullImage.width * 0.5).round();
      final cropH = (fullImage.height * 0.4).round();
      final cropX = ((fullImage.width * tapX) - cropW / 2).clamp(0, fullImage.width - cropW).round();
      final cropY = ((fullImage.height * tapY) - cropH / 2).clamp(0, fullImage.height - cropH).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        fullImage,
        Rect.fromLTWH(cropX.toDouble(), cropY.toDouble(), cropW.toDouble(), cropH.toDouble()),
        Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(cropW, cropH);
      final cropBytes = (await cropped.toByteData(format: ui.ImageByteFormat.png))!;

      final dir = await getApplicationDocumentsDirectory();
      final tmpPath = '${dir.path}/hotzone_crop_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(tmpPath).writeAsBytes(cropBytes.buffer.asUint8List());

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final inputImage = InputImage.fromFilePath(tmpPath);
      final result = await recognizer.processImage(inputImage);
      await recognizer.close();

      try { await File(tmpPath).delete(); } catch (_) {}

      final card = _parseContact(result.text);
      if (mounted) setState(() { _card = card; _processing = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.commonError}: $e')),
        );
      }
    }
  }

  _ContactCard _parseContact(String rawText) {
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final phoneRe = RegExp(r'[\+\(]?[\d\s\-\(\)]{7,}');
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
      } else if (name == null && line.length > 2 && line.length < 50 &&
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l10n.hotZoneTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: !_cameraReady
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0)))
          : LayoutBuilder(builder: (ctx, constraints) {
              return Stack(
                children: [
                  GestureDetector(
                    onTapDown: (d) => _captureAndAnalyze(d, constraints),
                    child: SizedBox.expand(
                      child: CameraPreview(_camCtrl!),
                    ),
                  ),

                  if (!_processing && _card == null)
                    Positioned(
                      bottom: 120,
                      left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.touch_app, color: Colors.white70, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.hotZoneTapHint,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                              const CircularProgressIndicator(color: Color(0xFF2CA5E0)),
                              const SizedBox(height: 16),
                              Text(l10n.hotZoneProcessing,
                                  style: const TextStyle(color: Colors.white, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_card != null)
                    Positioned(
                      left: 16, right: 16, bottom: 24,
                      child: _buildContactCard(_card!, isDark, textColor, l10n),
                    ),
                ],
              );
            }),
    );
  }

  Widget _buildContactCard(_ContactCard card, bool isDark, Color textColor, AppLocalizations l10n) {
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 4))],
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
                  width: 44, height: 44,
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
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                      if (card.extras.isNotEmpty)
                        Text(card.extras.first,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => setState(() => _card = null),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              children: [
                if (card.phone != null)
                  _cardRow(Icons.phone, card.phone!, isDark),
                if (card.email != null)
                  _cardRow(Icons.email_outlined, card.email!, isDark),
                if (card.url != null)
                  _cardRow(Icons.link, card.url!, isDark),
                if (card.phone == null && card.email == null && card.url == null && card.rawText.isNotEmpty)
                  _cardRow(Icons.text_fields, card.rawText.length > 120
                      ? '${card.rawText.substring(0, 120)}…'
                      : card.rawText, isDark),
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
                onPressed: () => setState(() => _card = null),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2CA5E0),
                  side: const BorderSide(color: Color(0xFF2CA5E0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardRow(IconData icon, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2CA5E0)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : const Color(0xFF333D4B),
                  height: 1.4,
                )),
          ),
        ],
      ),
    );
  }
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
