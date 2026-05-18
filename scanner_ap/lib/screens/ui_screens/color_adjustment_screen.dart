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
            backgroundColor: Colors.green,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Изменение цвета документа'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _resetValues,
            child: const Text('Сброс', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
      body: _originalImage == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Превью
                Expanded(
                  child: Container(
                    color: Colors.grey[200],
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_previewImage != null)
                          Center(
                            child: Image.memory(
                              _previewImage!,
                              gaplessPlayback: true,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        if (_isProcessing)
                          Container(
                            color: Colors.black26,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Слайдеры
                Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Яркость
                        buildSlider(
                          label: 'Яркость',
                          value: _brightness,
                          min: 0.5,
                          max: 2.0,
                          divisions: 30,
                          onChanged: (val) {
                            _brightness = val;
                            _scheduleUpdate();
                          },
                        ),

                        // Контраст
                        buildSlider(
                          label: 'Контраст',
                          value: _contrast,
                          min: 0.5,
                          max: 2.0,
                          divisions: 30,
                          onChanged: (val) {
                            _contrast = val;
                            _scheduleUpdate();
                          },
                        ),

                        // Насыщенность
                        buildSlider(
                          label: 'Насыщенность',
                          value: _saturation,
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          onChanged: (val) {
                            _saturation = val;
                            _scheduleUpdate();
                          },
                        ),

                        // Оттенок
                        buildSlider(
                          label: 'Оттенок',
                          value: _hue,
                          min: -180,
                          max: 180,
                          divisions: 72,
                          onChanged: (val) {
                            _hue = val;
                            _scheduleUpdate();
                          },
                        ),

                        const SizedBox(height: 16),

                        // Чекбоксы для фильтров
                        CheckboxListTile(
                          title: const Text('Удалить шумы'),
                          value: _removeNoise,
                          onChanged: (val) {
                            _removeNoise = val ?? false;
                            _scheduleUpdate();
                          },
                        ),

                        CheckboxListTile(
                          title: const Text('Повысить резкость'),
                          value: _sharpen,
                          onChanged: (val) {
                            _sharpen = val ?? false;
                            _scheduleUpdate();
                          },
                        ),

                        const SizedBox(height: 16),

                        // Кнопки действий
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing ? null : () => _pickImage(),
                                icon: const Icon(Icons.image),
                                label: const Text('Выбрать другое'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing ? null : _saveImage,
                                icon: const Icon(Icons.check),
                                label: const Text('Сохранить'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
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
    required Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.blue)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
