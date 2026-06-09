import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import '../../../models/save_format.dart';
import '../save_success_screen.dart';

class SaveOptionsScreen extends StatelessWidget {
  final List<String> sourceFilePaths;

  const SaveOptionsScreen({super.key, required this.sourceFilePaths});

  Future<String?> _showRenameDialog(BuildContext context, String currentFileName) async {
    final controller = TextEditingController(text: currentFileName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text('Имя файла', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'Имя файла',
            labelStyle: TextStyle(color: subColor),
            hintText: 'Введите имя',
            hintStyle: TextStyle(color: subColor),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE8EDF5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF2CA5E0)),
            ),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text('Отмена', style: TextStyle(color: subColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2CA5E0),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  Future<String> _saveAsImage(String fileName) async {
    if (sourceFilePaths.isEmpty) throw Exception('Нет исходного файла.');
    final imageBytes = await File(sourceFilePaths.first).readAsBytes();
    await ImageGallerySaverPlus.saveImage(imageBytes, name: fileName, quality: 100);
    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.jpg') ? fileName.substring(0, fileName.length - 4) : fileName;
    final internalPath = '${outputDir.path}/$baseName.jpg';
    await File(internalPath).writeAsBytes(imageBytes);
    return internalPath;
  }

  Future<String> _saveAsPdf(String fileName) async {
    if (sourceFilePaths.isEmpty) throw Exception('Нет исходных файлов.');
    final pdf = pw.Document();
    for (final path in sourceFilePaths) {
      final imageBytes = await File(path).readAsBytes();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(imageBytes))),
      ));
    }
    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.pdf') ? fileName.substring(0, fileName.length - 4) : fileName;
    final finalPath = '${outputDir.path}/$baseName.pdf';
    await File(finalPath).writeAsBytes(await pdf.save());
    return finalPath;
  }

  Future<void> _handleSave(BuildContext context, SaveFormat format) async {
    final defaultName = 'Scan_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final newFileName = await _showRenameDialog(context, defaultName);
    if (!context.mounted) return;
    if (newFileName == null || newFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранение отменено.')));
      return;
    }

    String finalPath = '';
    try {
      finalPath = format == SaveFormat.img
          ? await _saveAsImage(newFileName)
          : await _saveAsPdf(newFileName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('saved_document_paths') ?? [];
    if (!paths.contains(finalPath)) {
      paths.add(finalPath);
      await prefs.setStringList('saved_document_paths', paths);
    }

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => SaveSuccessScreen(filePath: finalPath, format: format)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.drive_file_rename_outline, color: const Color(0xFF2CA5E0), size: 72),
              const SizedBox(height: 16),
              Text(
                'Выберите формат сохранения',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '${sourceFilePaths.length} ${sourceFilePaths.length == 1 ? 'страница' : 'страниц(ы)'}',
                style: TextStyle(fontSize: 14, color: subColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              _buildOptionButton(
                icon: Icons.image_outlined,
                text: 'Сохранить как изображение',
                subText: '(JPG)',
                color: const Color(0xFF2CA5E0),
                onTap: () => _handleSave(context, SaveFormat.img),
              ),
              const SizedBox(height: 14),
              _buildOptionButton(
                icon: Icons.picture_as_pdf,
                text: 'Сохранить в PDF',
                subText: '(${sourceFilePaths.length} стр.)',
                color: Colors.red.shade600,
                onTap: () => _handleSave(context, SaveFormat.pdf),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String text,
    required Color color,
    required VoidCallback onTap,
    String subText = '',
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
            if (subText.isNotEmpty)
              Text(subText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
