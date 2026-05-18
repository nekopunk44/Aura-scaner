// save_options_passport.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../save_success_screen.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

enum SaveFormat { img, pdf }

class SaveOptionsScreen extends StatelessWidget {

  final List<String> sourceFilePaths;

  const SaveOptionsScreen({super.key, required this.sourceFilePaths});


  Future<String?> _showRenameDialog(BuildContext context, String currentFileName) async {
    TextEditingController controller = TextEditingController(text: currentFileName);

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Переименовать файл'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Имя файла',
              hintText: 'Введите новое имя',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Отмена'),
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
            ),
            ElevatedButton(
              child: const Text('Сохранить'),
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
            ),
          ],
        );
      },
    );
  }

  Future<String> _saveAsImage(BuildContext context, String fileName) async {
    if (sourceFilePaths.isEmpty) {
      throw Exception("Нет исходного файла для сохранения изображения.");
    }
    final sourceFile = File(sourceFilePaths.first);
    final imageBytes = await sourceFile.readAsBytes();

    final result = await ImageGallerySaverPlus.saveImage(
        imageBytes,
        name: fileName,
        quality: 100
    );

    if (result == null || (result is Map && result['isSuccess'] != true && result['isSuccess'] != 1)) {
      debugPrint('Предупреждение: Не удалось сохранить изображение в Галерею.');
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.jpg') ? fileName.substring(0, fileName.length - 4) : fileName;
    final internalPath = '${outputDir.path}/$baseName.jpg';

    final internalFile = File(internalPath);
    await internalFile.writeAsBytes(imageBytes);

    return internalPath;
  }

  Future<String> _saveAsPdf(BuildContext context, String fileName) async {
    final pdf = pw.Document();

    if (sourceFilePaths.isEmpty) {
      throw Exception("Нет исходных файлов для создания PDF.");
    }

    for (final path in sourceFilePaths) {
      final imageFile = File(path);
      final imageBytes = await imageFile.readAsBytes();
      final pdfImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pdfImage),
            );
          },
        ),
      );
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.pdf') ? fileName.substring(0, fileName.length - 4) : fileName;
    final finalPath = '${outputDir.path}/$baseName.pdf';
    final file = File(finalPath);

    await file.writeAsBytes(await pdf.save());

    return file.path;
  }


  Future<void> _handleSave(BuildContext context, SaveFormat format) async {
    String defaultName = 'Scan_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final newFileName = await _showRenameDialog(context, defaultName);

    if (!context.mounted) return;

    if (newFileName == null || newFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранение отменено.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Сохранение "$newFileName" в ${format == SaveFormat.img ? 'IMG...' : 'PDF...'}')),
    );

    String finalPath = '';
    try {
      if (format == SaveFormat.img) {
        if (sourceFilePaths.isEmpty) throw Exception("Отсутствует изображение для сохранения.");
        finalPath = await _saveAsImage(context, newFileName);
      } else {
        if (sourceFilePaths.isEmpty) throw Exception("Отсутствует изображение для сохранения.");
        finalPath = await _saveAsPdf(context, newFileName);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: ${e.toString()}')),
      );
      return;
    }


    final prefs = await SharedPreferences.getInstance();
    List<String> savedPaths = prefs.getStringList('saved_document_paths') ?? [];
    if (!savedPaths.contains(finalPath)) {
      savedPaths.add(finalPath);
      await prefs.setStringList('saved_document_paths', savedPaths);
    }

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (_) => SaveSuccessScreen(
              filePath: finalPath,
              format: format)),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.drive_file_rename_outline, color: Colors.blue, size: 80),
              const SizedBox(height: 20),
              const Text(
                'Выберите формат сохранения',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              _buildOptionButton(
                context,
                icon: Icons.image,
                text: 'Сохранить как IMG (Изображение)',
                color: Colors.lightBlue,
                subText: sourceFilePaths.isNotEmpty ? '(1 фото)' : '',
                onTap: () => _handleSave(context, SaveFormat.img),
              ),
              const SizedBox(height: 16),

              _buildOptionButton(
                context,
                icon: Icons.picture_as_pdf,
                text: 'Сохранить в PDF (Документ)',
                color: Colors.red,
                subText: sourceFilePaths.isNotEmpty ? '(${sourceFilePaths.length} фото)' : '',
                onTap: () => _handleSave(context, SaveFormat.pdf),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton(
      BuildContext context, {
        required IconData icon,
        required String text,
        required Color color,
        required VoidCallback onTap,
        String subText = '',
      }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    text,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),

          if (subText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                subText,
                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w300),
              ),
            ),
        ],
      ),
    );
  }
}
