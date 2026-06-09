import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../translate/apis/recognition_api.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  File? _selectedImage;
  String? _recognizedText;
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;
    if (!mounted) return;

    setState(() {
      _selectedImage = File(image.path);
      _recognizedText = null;
    });

    await _extractText(File(image.path));
  }

  Future<void> _extractText(File file) async {
    setState(() => _isProcessing = true);
    try {
      final result = await RecognitionApi.recognizeText(InputImage.fromFile(file));
      if (!mounted) return;
      setState(() => _recognizedText = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка OCR: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _copyText() {
    if (_recognizedText == null || _recognizedText!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _recognizedText!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Текст скопирован'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showPickerSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E2A3A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF2CA5E0)),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Color(0xFF2CA5E0)),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Распознавание текста'),
        centerTitle: true,
        actions: [
          if (_recognizedText != null && _recognizedText!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Копировать',
              onPressed: _copyText,
            ),
        ],
      ),
      body: _selectedImage == null
          ? _buildEmptyState(subColor)
          : _buildResult(subColor, cardBg, isDark),
      floatingActionButton: FloatingActionButton(
        onPressed: _showPickerSheet,
        backgroundColor: const Color(0xFF2CA5E0),
        child: const Icon(Icons.add_a_photo, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(Color subColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_fields, size: 72, color: subColor),
            const SizedBox(height: 16),
            Text(
              'Выберите фото для извлечения текста',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: subColor),
            ),
            const SizedBox(height: 8),
            Text(
              'Поддерживаются латиница и кириллица',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: subColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(Color subColor, Color cardBg, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(_selectedImage!, height: 220, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF2CA5E0)),
            )
          else if (_recognizedText == null || _recognizedText!.isEmpty)
            Center(
              child: Text(
                'Текст не обнаружен',
                style: TextStyle(color: subColor, fontSize: 16),
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Распознанный текст:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                TextButton.icon(
                  onPressed: _copyText,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Копировать'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE8EDF5),
                ),
              ),
              child: SelectableText(
                _recognizedText!,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
