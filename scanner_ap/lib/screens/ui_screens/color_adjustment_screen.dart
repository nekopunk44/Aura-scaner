import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/image_editing_service.dart';
import '../../l10n/app_localizations.dart';

const String _documentKey = 'saved_document_paths';

enum _Param { brightness, contrast, saturation, hue }

class ColorAdjustmentScreen extends StatefulWidget {
  final VoidCallback? onImageSaved;

  const ColorAdjustmentScreen({super.key, this.onImageSaved});

  @override
  State<ColorAdjustmentScreen> createState() => _ColorAdjustmentScreenState();
}

class _ColorAdjustmentScreenState extends State<ColorAdjustmentScreen> {
  Uint8List? _originalImage;
  Uint8List? _previewImage;
  bool _isProcessing = false;

  double _brightness = 1.0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  double _hue = 0.0;
  bool _removeNoise = false;
  bool _sharpen = false;
  Timer? _debounce;

  _Param _activeParam = _Param.brightness;

  @override
  void initState() {
    super.initState();
    _pickImage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleUpdate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _updatePreview);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 88,
    );
    if (picked == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    _originalImage = await File(picked.path).readAsBytes();
    _previewImage = _originalImage;
    if (!mounted) return;
    setState(() {});
    _scheduleUpdate();
  }

  Future<void> _updatePreview() async {
    if (_originalImage == null) return;
    setState(() => _isProcessing = true);

    try {
      _previewImage = await ImageEditingService.applyFilters(
        imageBytes: _originalImage!,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        hue: _hue,
        sharpenImage: _sharpen,
        removeNoise: _removeNoise,
      );
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).processingError}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveImage() async {
    if (_previewImage == null) return;

    try {
      setState(() => _isProcessing = true);

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'adjusted_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${dir.path}/$fileName';

      await File(filePath).writeAsBytes(_previewImage!);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(filePath)) {
        paths.add(filePath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onImageSaved?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).snackSaved(fileName)),
            backgroundColor: const Color(0xFF2CA5E0),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).saveError}: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetValues() {
    setState(() {
      _brightness = 1.0;
      _contrast = 1.0;
      _saturation = 1.0;
      _hue = 0.0;
      _removeNoise = false;
      _sharpen = false;
    });
    _scheduleUpdate();
  }

  ({double value, double min, double max, int divisions, String unit})
  _activeParamSpec() {
    switch (_activeParam) {
      case _Param.brightness:
        return (
          value: _brightness,
          min: 0.5,
          max: 2.0,
          divisions: 30,
          unit: '',
        );
      case _Param.contrast:
        return (value: _contrast, min: 0.5, max: 2.0, divisions: 30, unit: '');
      case _Param.saturation:
        return (
          value: _saturation,
          min: 0.0,
          max: 2.0,
          divisions: 40,
          unit: '',
        );
      case _Param.hue:
        return (value: _hue, min: -180, max: 180, divisions: 72, unit: '°');
    }
  }

  void _setActiveValue(double v) {
    switch (_activeParam) {
      case _Param.brightness:
        _brightness = v;
      case _Param.contrast:
        _contrast = v;
      case _Param.saturation:
        _saturation = v;
      case _Param.hue:
        _hue = v;
    }
    _scheduleUpdate();
  }

  bool _isDefault(_Param p) {
    switch (p) {
      case _Param.brightness:
        return _brightness == 1.0;
      case _Param.contrast:
        return _contrast == 1.0;
      case _Param.saturation:
        return _saturation == 1.0;
      case _Param.hue:
        return _hue == 0.0;
    }
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
    final chipBg = isDark ? const Color(0xFF2A3A4F) : const Color(0xFFEEF3FA);
    const accent = Color(0xFF2CA5E0);

    final spec = _activeParamSpec();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          l10n.featColorAdjust,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _resetValues,
            child: Text(l10n.reset, style: const TextStyle(color: accent)),
          ),
        ],
      ),
      body: _originalImage == null
          ? const Center(child: CircularProgressIndicator(color: accent))
          : LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: previewBg,
                        child: _previewImage == null
                            ? const SizedBox.shrink()
                            : InteractiveViewer(
                                minScale: 0.8,
                                maxScale: 4,
                                child: Center(
                                  child: Image.memory(
                                    _previewImage!,
                                    gaplessPlayback: true,
                                    fit: BoxFit.contain,
                                    width: constraints.maxWidth,
                                    height: constraints.maxHeight,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ControlsOverlay(
                        maxHeight: constraints.maxHeight * 0.48,
                        cardBg: cardBg,
                        bottomInset: MediaQuery.of(context).padding.bottom,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _ParamChip(
                                    label: l10n.colorBrightness,
                                    icon: Icons.brightness_6_outlined,
                                    active: _activeParam == _Param.brightness,
                                    modified: !_isDefault(_Param.brightness),
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    subColor: subColor,
                                    onTap: () => setState(
                                      () => _activeParam = _Param.brightness,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _ParamChip(
                                    label: l10n.colorContrast,
                                    icon: Icons.contrast,
                                    active: _activeParam == _Param.contrast,
                                    modified: !_isDefault(_Param.contrast),
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    subColor: subColor,
                                    onTap: () => setState(
                                      () => _activeParam = _Param.contrast,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _ParamChip(
                                    label: l10n.colorSaturationShort,
                                    icon: Icons.palette_outlined,
                                    active: _activeParam == _Param.saturation,
                                    modified: !_isDefault(_Param.saturation),
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    subColor: subColor,
                                    onTap: () => setState(
                                      () => _activeParam = _Param.saturation,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _ParamChip(
                                    label: l10n.colorHue,
                                    icon: Icons.color_lens_outlined,
                                    active: _activeParam == _Param.hue,
                                    modified: !_isDefault(_Param.hue),
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    subColor: subColor,
                                    onTap: () => setState(
                                      () => _activeParam = _Param.hue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _activeParamLabel(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subColor,
                                  ),
                                ),
                                Text(
                                  '${spec.value.toStringAsFixed(_activeParam == _Param.hue ? 0 : 2)}${spec.unit}',
                                  style: const TextStyle(
                                    color: accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: accent,
                                thumbColor: accent,
                                overlayColor: accent.withValues(alpha: 0.12),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: spec.value,
                                min: spec.min,
                                max: spec.max,
                                divisions: spec.divisions,
                                onChanged: _setActiveValue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: _ToggleTile(
                                    label: l10n.colorDenoise,
                                    icon: Icons.blur_on,
                                    value: _removeNoise,
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    onChanged: (v) {
                                      setState(() => _removeNoise = v);
                                      _scheduleUpdate();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _ToggleTile(
                                    label: l10n.colorSharpness,
                                    icon: Icons.deblur,
                                    value: _sharpen,
                                    accent: accent,
                                    bg: chipBg,
                                    textColor: textColor,
                                    onChanged: (v) {
                                      setState(() => _sharpen = v);
                                      _scheduleUpdate();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isProcessing
                                        ? null
                                        : _pickImage,
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
                                    onPressed: _isProcessing
                                        ? null
                                        : _saveImage,
                                    icon: const Icon(Icons.check, size: 18),
                                    label: Text(l10n.actionSave),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accent,
                                      disabledBackgroundColor: accent
                                          .withValues(alpha: 0.4),
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
                    ),
                    if (_isProcessing)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  String _activeParamLabel() {
    final l10n = AppLocalizations.of(context);
    switch (_activeParam) {
      case _Param.brightness:
        return l10n.colorBrightness;
      case _Param.contrast:
        return l10n.colorContrast;
      case _Param.saturation:
        return l10n.colorSaturation;
      case _Param.hue:
        return l10n.colorHue;
    }
  }
}

class _ControlsOverlay extends StatelessWidget {
  final double maxHeight;
  final double bottomInset;
  final Color cardBg;
  final Widget child;

  const _ControlsOverlay({
    required this.maxHeight,
    required this.bottomInset,
    required this.cardBg,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset + 16),
          decoration: BoxDecoration(
            color: cardBg.withValues(alpha: 0.86),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool modified;
  final Color accent;
  final Color bg;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _ParamChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.modified,
    required this.accent,
    required this.bg,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? accent : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (modified && !active) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool value;
  final Color accent;
  final Color bg;
  final Color textColor;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.label,
    required this.icon,
    required this.value,
    required this.accent,
    required this.bg,
    required this.textColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value ? accent.withValues(alpha: 0.12) : bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? accent : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: value ? accent : textColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: value ? accent : textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
