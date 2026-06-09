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
    // Ограничиваем размер на этапе выбора: фильтры обрабатываются попиксельно
    // в Dart, а 12MP фото даёт >10с задержки.
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
      final fileName = 'cleaned_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
          backgroundColor: const Color(0xFF2CA5E0),
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
        title: Text('Убрать пятна', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _originalImage == null
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : Column(
              children: [
                Expanded(
                  child: Container(
                    color: previewBg,
                    child: Center(
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Color(0xFF2CA5E0))
                          : _previewImage != null
                              ? Image.memory(_previewImage!)
                              : const SizedBox.shrink(),
                    ),
                  ),
                ),
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.all(16),
                  child: RadioGroup<int>(
                    groupValue: _selectedFilter,
                    onChanged: (value) {
                      if (value == null || _isProcessing) return;
                      setState(() => _selectedFilter = value);
                      _applyFilter();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Выберите фильтр:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: textColor)),
                        const SizedBox(height: 8),
                        RadioListTile<int>(
                          title: Text('Медианный фильтр', style: TextStyle(color: textColor, fontSize: 14)),
                          subtitle: Text('Лучший для пятен и артефактов', style: TextStyle(color: subColor, fontSize: 12)),
                          value: 0,
                          activeColor: const Color(0xFF2CA5E0),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<int>(
                          title: Text('Размытие Гаусса', style: TextStyle(color: textColor, fontSize: 14)),
                          subtitle: Text('Мягче, для деликатных документов', style: TextStyle(color: subColor, fontSize: 12)),
                          value: 1,
                          activeColor: const Color(0xFF2CA5E0),
                          contentPadding: EdgeInsets.zero,
                        ),
                        RadioListTile<int>(
                          title: Text('Комбинированный', style: TextStyle(color: textColor, fontSize: 14)),
                          subtitle: Text('Медиана + размытие — рекомендуется', style: TextStyle(color: subColor, fontSize: 12)),
                          value: 2,
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
