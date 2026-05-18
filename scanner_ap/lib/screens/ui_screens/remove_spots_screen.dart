import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/image_editing_service.dart';

const String _documentKey = 'saved_document_paths';

class RemoveSpotsScreen extends StatefulWidget {
  final VoidCallback? onImageSaved;

  const RemoveSpotsScreen({super.key, this.onImageSaved});

  @override
  State<RemoveSpotsScreen> createState() => _RemoveSpotsScreenState();
}

class _RemoveSpotsScreenState extends State<RemoveSpotsScreen> {
  Uint8List? _originalImage;
  Uint8List? _previewImage;
  bool _isProcessing = false;
  int _selectedFilter = 2;

  @override
  void initState() {
    super.initState();
    _pickImage();
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
    if (!mounted) return;
    setState(() {});
    _applyFilter();
  }

  Future<void> _applyFilter() async {
    if (_originalImage == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isProcessing = true);

    try {
      _previewImage = await ImageEditingService.removeSpots(
        imageBytes: _originalImage!,
        filterType: _selectedFilter,
      );
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка обработки: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _saveImage() async {
    if (_previewImage == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      setState(() => _isProcessing = true);

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'cleaned_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${dir.path}/$fileName';

      await File(filePath).writeAsBytes(_previewImage!);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(filePath)) {
        paths.add(filePath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onImageSaved?.call();

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Сохранено: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Убрать метки и пятна'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _originalImage == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: _isProcessing
                          ? const CircularProgressIndicator()
                          : _previewImage != null
                              ? Image.memory(_previewImage!)
                              : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: RadioGroup<int>(
                    groupValue: _selectedFilter,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedFilter = value);
                      _applyFilter();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Выберите фильтр:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        const RadioListTile<int>(
                          title: Text('Медианный фильтр'),
                          subtitle: Text('Лучший для пятен и артефактов'),
                          value: 0,
                        ),
                        const RadioListTile<int>(
                          title: Text('Размытие Гаусса'),
                          subtitle: Text('Мягче, подходит для деликатных документов'),
                          value: 1,
                        ),
                        const RadioListTile<int>(
                          title: Text('Комбинированный (рекомендуется)'),
                          subtitle: Text('Медиана + размытие для лучшего результата'),
                          value: 2,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isProcessing ? null : _pickImage,
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
}
