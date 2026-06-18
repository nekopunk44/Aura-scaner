import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/signature_storage_service.dart';
import 'signature_picker_sheet.dart';

class ImageSignatureEditorScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const ImageSignatureEditorScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  @override
  State<ImageSignatureEditorScreen> createState() =>
      _ImageSignatureEditorScreenState();
}

class _ImageSignatureEditorScreenState extends State<ImageSignatureEditorScreen> {
  final _signatureStorage = SignatureStorageService();
  final _captureKey = GlobalKey();
  final _canvasKey = GlobalKey();

  Uint8List? _signatureBytes;
  String? _selectedSignatureId;
  bool _isSaving = false;
  bool _isPreparingSignature = false;
  double _imageAspectRatio = 1;
  final List<_PlacedSignature> _signatures = [];

  @override
  void initState() {
    super.initState();
    _loadImageMetadata();
  }

  Future<void> _loadImageMetadata() async {
    final bytes = await File(widget.filePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null || !mounted) return;
    setState(() {
      _imageAspectRatio = decoded.width / decoded.height;
    });
  }

  String _placeHint(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Нажмите на изображение, чтобы поставить подпись'
        : 'Tap the image to place the signature';
  }

  String _editHint(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Подпись можно двигать и менять размер'
        : 'You can drag and resize the signature';
  }

  String _addedHint(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Подпись добавлена'
        : 'Signature added';
  }

  String _selectedLabel(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru'
        ? 'Подпись'
        : 'Signature';
  }

  Future<bool> _ensureSignatureReady() async {
    if (!mounted) return false;
    final result = await SignaturePickerSheet.pickSignature(
      context,
      storage: _signatureStorage,
    );
    if (!mounted || result == null) return false;
    _signatureBytes = result;
    return true;
  }

  Future<Size> _measureSignature(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  _PlacedSignature? _findSignature(String? id) {
    if (id == null) return null;
    try {
      return _signatures.firstWhere((signature) => signature.id == id);
    } catch (_) {
      return null;
    }
  }

  void _updateSignature(
    String id,
    _PlacedSignature Function(_PlacedSignature signature) updater,
  ) {
    final index = _signatures.indexWhere((signature) => signature.id == id);
    if (index == -1) return;
    setState(() {
      _signatures[index] = updater(_signatures[index]);
    });
  }

  Offset _clampPosition({
    required Offset position,
    required Size signatureSize,
    required Size canvasSize,
  }) {
    return Offset(
      position.dx.clamp(8.0, canvasSize.width - signatureSize.width - 8.0),
      position.dy.clamp(8.0, canvasSize.height - signatureSize.height - 8.0),
    );
  }

  void _moveSignature(String id, Offset delta) {
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size;
    final signature = _findSignature(id);
    if (canvasSize == null || signature == null) return;

    _updateSignature(
      id,
      (current) => current.copyWith(
        position: _clampPosition(
          position: current.position + delta,
          signatureSize: current.size,
          canvasSize: canvasSize,
        ),
      ),
    );
  }

  void _resizeSignature(String id, Offset delta) {
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    final canvasSize = renderBox?.size;
    final signature = _findSignature(id);
    if (canvasSize == null || signature == null) return;

    final aspectRatio = signature.size.width / signature.size.height;
    final width = (signature.size.width + delta.dx).clamp(90.0, canvasSize.width * 0.78);
    final height = (width / aspectRatio).clamp(34.0, canvasSize.height * 0.5);
    final nextSize = Size(width, height);
    final nextPosition = _clampPosition(
      position: signature.position,
      signatureSize: nextSize,
      canvasSize: canvasSize,
    );

    _updateSignature(
      id,
      (current) => current.copyWith(position: nextPosition, size: nextSize),
    );
  }

  Future<void> _placeSignature(TapUpDetails details) async {
    if (_isPreparingSignature) return;
    setState(() => _isPreparingSignature = true);
    try {
      final ready = await _ensureSignatureReady();
      if (!mounted || !ready || _signatureBytes == null) return;

      final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
      final canvasSize = renderBox?.size;
      if (canvasSize == null) return;

      final originalSize = await _measureSignature(_signatureBytes!);
      if (!mounted) return;

      const targetWidth = 160.0;
      final aspectRatio = originalSize.width == 0
          ? 2.8
          : originalSize.width / originalSize.height;
      final width = targetWidth.clamp(110.0, canvasSize.width * 0.52);
      final height = (width / aspectRatio).clamp(40.0, 120.0);
      final size = Size(width, height);
      final position = _clampPosition(
        position: Offset(
          details.localPosition.dx - width / 2,
          details.localPosition.dy - height / 2,
        ),
        signatureSize: size,
        canvasSize: canvasSize,
      );

      final placed = _PlacedSignature(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bytes: _signatureBytes!,
        position: position,
        size: size,
      );

      setState(() {
        _signatures.add(placed);
        _selectedSignatureId = placed.id;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_addedHint(context)}. ${_editHint(context)}')),
      );
    } finally {
      if (mounted) setState(() => _isPreparingSignature = false);
    }
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Capture unavailable');

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('Encoding failed');

      final dir = await getApplicationDocumentsDirectory();
      final baseName = p.basenameWithoutExtension(widget.fileName);
      final outputPath =
          '${dir.path}/${baseName}_signed_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outputPath).writeAsBytes(byteData.buffer.asUint8List());

      if (!mounted) return;
      Navigator.pop(context, outputPath);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.featSignature,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.actionDone,
            onPressed: _signatures.isEmpty || _isSaving ? null : _saveImage,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.check, color: textColor),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2A3A) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined, color: Color(0xFF2CA5E0)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _placeHint(context),
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _imageAspectRatio,
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: GestureDetector(
                        key: _canvasKey,
                        onTapUp: _placeSignature,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.file(
                                File(widget.filePath),
                                fit: BoxFit.cover,
                              ),
                            ),
                            for (final signature in _signatures)
                              Positioned(
                                left: signature.position.dx,
                                top: signature.position.dy,
                                width: signature.size.width,
                                height: signature.size.height,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _selectedSignatureId = signature.id;
                                  }),
                                  onPanUpdate: (details) =>
                                      _moveSignature(signature.id, details.delta),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      TweenAnimationBuilder<double>(
                                        key: ValueKey('image-signature-${signature.id}'),
                                        tween: Tween(begin: 0.92, end: 1),
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutBack,
                                        builder: (context, scale, child) {
                                          return Transform.scale(scale: scale, child: child);
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 120),
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: _selectedSignatureId == signature.id
                                                ? const Color(0xFF2CA5E0).withValues(alpha: 0.08)
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: _selectedSignatureId == signature.id
                                                  ? const Color(0xFF2CA5E0)
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                            boxShadow: _selectedSignatureId == signature.id
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(0xFF2CA5E0)
                                                          .withValues(alpha: 0.18),
                                                      blurRadius: 16,
                                                      spreadRadius: 2,
                                                    ),
                                                  ]
                                                : const [],
                                          ),
                                          child: Image.memory(
                                            signature.bytes,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      if (_selectedSignatureId == signature.id)
                                        Positioned(
                                          left: 6,
                                          top: -16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2CA5E0),
                                              borderRadius: BorderRadius.circular(999),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF2CA5E0)
                                                      .withValues(alpha: 0.25),
                                                  blurRadius: 12,
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              _selectedLabel(context),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (_selectedSignatureId == signature.id)
                                        Positioned(
                                          right: -10,
                                          bottom: -10,
                                          child: GestureDetector(
                                            onPanUpdate: (details) => _resizeSignature(
                                              signature.id,
                                              details.delta,
                                            ),
                                            onTap: () {},
                                            child: Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2CA5E0),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.open_in_full,
                                                color: Colors.white,
                                                size: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectedSignatureId == null
                          ? null
                          : () {
                              setState(() {
                                _signatures.removeWhere(
                                  (signature) => signature.id == _selectedSignatureId,
                                );
                                _selectedSignatureId = null;
                              });
                            },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(l10n.actionDelete),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _saveImage,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(l10n.actionDone),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2CA5E0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
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

class _PlacedSignature {
  final String id;
  final Uint8List bytes;
  final Offset position;
  final Size size;

  const _PlacedSignature({
    required this.id,
    required this.bytes,
    required this.position,
    required this.size,
  });

  _PlacedSignature copyWith({
    String? id,
    Uint8List? bytes,
    Offset? position,
    Size? size,
  }) {
    return _PlacedSignature(
      id: id ?? this.id,
      bytes: bytes ?? this.bytes,
      position: position ?? this.position,
      size: size ?? this.size,
    );
  }
}
