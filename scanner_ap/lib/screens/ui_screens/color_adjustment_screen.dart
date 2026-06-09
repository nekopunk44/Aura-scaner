import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/image_editing_service.dart';

const String _documentKey = 'saved_document_paths';

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
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    _originalImage = await File(picked.path).readAsBytes();
    _previewImage = _originalImage;
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
        SnackBar(content: Text('Ошибка обработки: $e')),
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
            content: Text('Сохранено: $fileName'),
            backgroundColor: const Color(0xFF2CA5E0),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final previewBg = isDark ? const Color(0xFF0A1118) : const Color(0xFFE8EDF5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('Настройка цвета', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _resetValues,
            child: const Text('Сброс', style: TextStyle(color: Color(0xFF2CA5E0))),
          ),
        ],
      ),
      body: _originalImage == null
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: previewBg,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_previewImage != null)
                          Center(child: Image.memory(_previewImage!, gaplessPlayback: true))
                        else
                          const SizedBox.shrink(),
                        if (_isProcessing)
                          Container(
                            color: Colors.black38,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: cardBg,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        buildSlider(label: 'Яркость', value: _brightness, min: 0.5, max: 2.0, divisions: 30, textColor: textColor, onChanged: (val) { _brightness = val; _scheduleUpdate(); }),
                        buildSlider(label: 'Контраст', value: _contrast, min: 0.5, max: 2.0, divisions: 30, textColor: textColor, onChanged: (val) { _contrast = val; _scheduleUpdate(); }),
                        buildSlider(label: 'Насыщенность', value: _saturation, min: 0.0, max: 2.0, divisions: 40, textColor: textColor, onChanged: (val) { _saturation = val; _scheduleUpdate(); }),
                        buildSlider(label: 'Оттенок', value: _hue, min: -180, max: 180, divisions: 72, textColor: textColor, onChanged: (val) { _hue = val; _scheduleUpdate(); }),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: Text('Удалить шумы', style: TextStyle(color: textColor, fontSize: 14)),
                          subtitle: Text('Сглаживание артефактов', style: TextStyle(color: subColor, fontSize: 12)),
                          value: _removeNoise,
                          onChanged: (val) { _removeNoise = val ?? false; _scheduleUpdate(); },
                          activeColor: const Color(0xFF2CA5E0),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: Text('Повысить резкость', style: TextStyle(color: textColor, fontSize: 14)),
                          subtitle: Text('Чёткость краёв и текста', style: TextStyle(color: subColor, fontSize: 12)),
                          value: _sharpen,
                          onChanged: (val) { _sharpen = val ?? false; _scheduleUpdate(); },
                          activeColor: const Color(0xFF2CA5E0),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isProcessing ? null : _pickImage,
                                icon: const Icon(Icons.image, size: 18),
                                label: const Text('Другое фото'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2CA5E0),
                                  side: const BorderSide(color: Color(0xFF2CA5E0)),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing ? null : _saveImage,
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('Сохранить'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2CA5E0),
                                  disabledBackgroundColor: const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Color textColor,
    required Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor)),
              Text(value.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF2CA5E0), fontSize: 13)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: const Color(0xFF2CA5E0), thumbColor: const Color(0xFF2CA5E0)),
            child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
