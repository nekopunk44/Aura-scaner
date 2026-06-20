import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/document_registry.dart';
import '../../services/image_editing_service.dart';

const String _documentKey = 'saved_document_paths';

class RemoveSpotsScreen extends StatefulWidget {
  final VoidCallback? onImageSaved;
  final String? initialImagePath;
  final bool autoProcessOnOpen;
  final bool startInManualMode;

  const RemoveSpotsScreen({
    super.key,
    this.onImageSaved,
    this.initialImagePath,
    this.autoProcessOnOpen = true,
    this.startInManualMode = false,
  });

  @override
  State<RemoveSpotsScreen> createState() => _RemoveSpotsScreenState();
}

class _RemoveSpotsScreenState extends State<RemoveSpotsScreen> {
  Uint8List? _originalImage;
  Uint8List? _previewImage;
  Size? _imageSize;
  bool _isProcessing = false;
  bool _manualMode = false;
  int _selectedFilter = 2;
  int _lastManualTouchMs = 0;
  List<Offset> _detectedSpots = const [];
  List<Offset> _manualSpots = const [];
  bool _showSpotMarkers = false;
  Timer? _markerTimer;

  @override
  void initState() {
    super.initState();
    _manualMode = widget.startInManualMode;
    _bootstrap();
  }

  @override
  void dispose() {
    _markerTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final initialPath = widget.initialImagePath;
    if (initialPath != null && initialPath.isNotEmpty) {
      await _loadImageFromFile(
        File(initialPath),
        autoProcess: widget.autoProcessOnOpen && !_manualMode,
      );
      return;
    }

    await _pickImage(autoProcess: widget.autoProcessOnOpen && !_manualMode);
  }

  Future<void> _pickImage({bool autoProcess = true}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 88,
    );
    if (picked == null) {
      if (mounted && _originalImage == null) {
        Navigator.pop(context);
      }
      return;
    }

    await _loadImageFromFile(File(picked.path), autoProcess: autoProcess);
  }

  Future<void> _loadImageFromFile(
    File file, {
    required bool autoProcess,
  }) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() {
      _originalImage = bytes;
      _previewImage = bytes;
      _imageSize = _decodeSize(bytes);
      _detectedSpots = const [];
      _manualSpots = const [];
      _showSpotMarkers = false;
    });

    if (autoProcess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_applyAutoCleanup(showMarkers: true));
        }
      });
    }
  }

  Size? _decodeSize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return Size(decoded.width.toDouble(), decoded.height.toDouble());
  }

  Future<void> _applyAutoCleanup({bool showMarkers = false}) async {
    if (_originalImage == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isProcessing = true);

    try {
      final detected = await ImageEditingService.detectSpotMarkers(
        imageBytes: _originalImage!,
      );
      final cleaned = await ImageEditingService.removeSpots(
        imageBytes: _originalImage!,
        filterType: _selectedFilter,
      );
      if (!mounted) return;

      _markerTimer?.cancel();
      setState(() {
        _previewImage = cleaned;
        _imageSize = _decodeSize(cleaned);
        _detectedSpots = detected;
        _manualSpots = const [];
        _showSpotMarkers = showMarkers && detected.isNotEmpty;
      });

      if (showMarkers && detected.isNotEmpty) {
        _markerTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) {
            setState(() => _showSpotMarkers = false);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).processingError}: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _applyManualCleanupAt(
    Offset localPosition,
    Size canvasSize,
  ) async {
    if (_previewImage == null || canvasSize.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    final normalized = Offset(
      (localPosition.dx / canvasSize.width).clamp(0.0, 1.0),
      (localPosition.dy / canvasSize.height).clamp(0.0, 1.0),
    );

    setState(() => _isProcessing = true);
    try {
      final cleaned = await ImageEditingService.removeSpotAt(
        imageBytes: _previewImage!,
        normalizedCenter: normalized,
      );
      if (!mounted) return;
      setState(() {
        _previewImage = cleaned;
        _imageSize = _decodeSize(cleaned);
        _manualSpots = [..._manualSpots.take(24), normalized];
        _showSpotMarkers = false;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).processingError}: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleManualGesture(Offset localPosition, Size canvasSize) {
    if (!_manualMode || _isProcessing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastManualTouchMs < 90) return;
    _lastManualTouchMs = now;
    unawaited(_applyManualCleanupAt(localPosition, canvasSize));
  }

  void _switchMode(bool manualMode) {
    if (_manualMode == manualMode || _originalImage == null) return;
    _markerTimer?.cancel();

    setState(() {
      _manualMode = manualMode;
      _previewImage = _originalImage;
      _imageSize = _decodeSize(_originalImage!);
      _detectedSpots = const [];
      _manualSpots = const [];
      _showSpotMarkers = false;
    });

    if (!manualMode) {
      unawaited(_applyAutoCleanup(showMarkers: true));
    }
  }

  Future<void> _saveImage() async {
    if (_previewImage == null) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      setState(() => _isProcessing = true);

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'cleaned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${dir.path}/$fileName';

      await File(filePath).writeAsBytes(_previewImage!);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(filePath)) {
        paths.add(filePath);
        await prefs.setStringList(_documentKey, paths);
      }

      await DocumentRegistry().load();
      await DocumentRegistry().add(
        DocEntry(
          localPath: filePath,
          remoteId: null,
          name: DocumentRegistry.nameFromPath(filePath),
        ),
      );

      widget.onImageSaved?.call();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).savedPlain),
          backgroundColor: const Color(0xFF2CA5E0),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).saveError}: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Widget _buildModeToggle(
    AppLocalizations l10n,
    Color accent,
    Color textColor,
  ) {
    Widget segment({
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.white : textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          segment(
            label: l10n.camAutoLabel,
            active: !_manualMode,
            onTap: () => _switchMode(false),
          ),
          segment(
            label: l10n.camManualLabel,
            active: _manualMode,
            onTap: () => _switchMode(true),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoFilterChips(
    AppLocalizations l10n,
    Color accent,
    Color textColor,
    Color subColor,
  ) {
    Widget chip({
      required String title,
      required String subtitle,
      required int value,
    }) {
      final active = _selectedFilter == value;
      return GestureDetector(
        onTap: _isProcessing
            ? null
            : () {
                setState(() => _selectedFilter = value);
                unawaited(_applyAutoCleanup(showMarkers: true));
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 162,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? accent : subColor.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: subColor, fontSize: 11, height: 1.25),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            title: l10n.spotsMedianTitle,
            subtitle: l10n.spotsMedianSub,
            value: 0,
          ),
          const SizedBox(width: 8),
          chip(
            title: l10n.spotsGaussTitle,
            subtitle: l10n.spotsGaussSub,
            value: 1,
          ),
          const SizedBox(width: 8),
          chip(
            title: l10n.spotsCombinedTitle,
            subtitle: l10n.spotsCombinedSub,
            value: 2,
          ),
        ],
      ),
    );
  }

  Size _containSize(Size imageSize, Size boxSize) {
    final imageRatio = imageSize.width / imageSize.height;
    final boxRatio = boxSize.width / boxSize.height;
    if (imageRatio > boxRatio) {
      return Size(boxSize.width, boxSize.width / imageRatio);
    }
    return Size(boxSize.height * imageRatio, boxSize.height);
  }

  Widget _buildPreviewStage(Color previewBg) {
    if (_previewImage == null || _imageSize == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = _containSize(
          _imageSize!,
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        return Container(
          color: previewBg,
          child: Center(
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _manualMode
                    ? (details) =>
                          _handleManualGesture(details.localPosition, fitted)
                    : null,
                onPanUpdate: _manualMode
                    ? (details) =>
                          _handleManualGesture(details.localPosition, fitted)
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(_previewImage!, fit: BoxFit.fill),
                    if (_showSpotMarkers || _manualSpots.isNotEmpty)
                      CustomPaint(
                        painter: _SpotOverlayPainter(
                          autoSpots: _showSpotMarkers
                              ? _detectedSpots
                              : const [],
                          manualSpots: _manualSpots,
                        ),
                      ),
                    if (_isProcessing)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2CA5E0),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? const Color(0xFF0F1923)
        : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final previewBg = isDark
        ? const Color(0xFF0A1118)
        : const Color(0xFFE8EDF5);
    const accent = Color(0xFF2CA5E0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          l10n.featRemoveSpots,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _originalImage == null
          ? const Center(child: CircularProgressIndicator(color: accent))
          : Column(
              children: [
                Expanded(child: _buildPreviewStage(previewBg)),
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildModeToggle(l10n, accent, textColor),
                      const SizedBox(height: 12),
                      Text(
                        _manualMode
                            ? 'Тапайте или ведите по пятнам на фото, чтобы убрать их локально.'
                            : 'Приложение автоматически ищет дефекты, подсвечивает их и очищает фото.',
                        style: TextStyle(
                          color: subColor,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_manualMode)
                        _buildAutoFilterChips(
                          l10n,
                          accent,
                          textColor,
                          subColor,
                        ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing
                                  ? null
                                  : () => _pickImage(autoProcess: !_manualMode),
                              icon: const Icon(Icons.image, size: 18),
                              label: Text(l10n.otherPhoto),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: const BorderSide(color: accent),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _saveImage,
                              icon: const Icon(Icons.check, size: 18),
                              label: Text(l10n.actionSave),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                disabledBackgroundColor: accent.withValues(
                                  alpha: 0.4,
                                ),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SpotOverlayPainter extends CustomPainter {
  const _SpotOverlayPainter({
    required this.autoSpots,
    required this.manualSpots,
  });

  final List<Offset> autoSpots;
  final List<Offset> manualSpots;

  @override
  void paint(Canvas canvas, Size size) {
    final autoStroke = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final autoFill = Paint()
      ..color = const Color(0x33FFD54F)
      ..style = PaintingStyle.fill;
    final manualStroke = Paint()
      ..color = const Color(0xFF2CA5E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final manualFill = Paint()
      ..color = const Color(0x332CA5E0)
      ..style = PaintingStyle.fill;

    for (final spot in autoSpots) {
      final center = Offset(spot.dx * size.width, spot.dy * size.height);
      canvas.drawCircle(center, 18, autoFill);
      canvas.drawCircle(center, 18, autoStroke);
    }

    for (final spot in manualSpots) {
      final center = Offset(spot.dx * size.width, spot.dy * size.height);
      canvas.drawCircle(center, 22, manualFill);
      canvas.drawCircle(center, 22, manualStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotOverlayPainter oldDelegate) {
    return oldDelegate.autoSpots != autoSpots ||
        oldDelegate.manualSpots != manualSpots;
  }
}
