// Экран выбора формата сохранения для обычных документов.
//
// Форматы:
// - IMG — сохраняет только первую страницу как JPG в галерею.
//   Доступен только при одной странице.
// - PDF — создаёт PDF из всех страниц. Применяет фильтры редактора
//   (поворот, яркость, контраст, чёрно-белый) перед сохранением.
//
// Перед сохранением показывает диалог переименования файла.
// После успешного сохранения переходит на SaveSuccessScreen.
//
// Файл сохраняется в: getApplicationDocumentsDirectory()/documents/
// Путь добавляется в SharedPreferences по ключу 'documents'.
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image/image.dart' as img_lib;
import 'document_camera_edit.dart';
import '../main_screen/app_tabs_screen.dart';
import '../../../services/document_sync_service.dart';
import '../../../services/document_registry.dart';


enum SaveFormat { img, pdf }

class SaveOptionsScreen extends StatefulWidget {
  final List<String> sourceFilePaths;
  final List<ImageEditState>? editStates;

  const SaveOptionsScreen({
    super.key,
    required this.sourceFilePaths,
    required this.editStates,
  });

  @override
  State<SaveOptionsScreen> createState() => _SaveOptionsScreenState();
}

class _SaveOptionsScreenState extends State<SaveOptionsScreen> {
  bool _isSaving = false;
  String? _finalPath;
  SaveFormat? _finalFormat;
  String? _errorMessage;


  Future<File> _applyFiltersAndSaveTemp(ImageEditState state, int index) async {
    final originalFile = File(state.path);
    final imageBytes = await originalFile.readAsBytes();

    img_lib.Image? image = img_lib.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Не удалось декодировать изображение для страницы ${index + 1}');
    }

    // Применение Поворота и Ч/Б
    if (state.rotation != 0.0) {
      int angle = state.rotation.round();
      if (angle == 90 || angle == 180 || angle == 270) {
        image = img_lib.copyRotate(image, angle: angle);
      }
    }
    if (state.isGrayScale) {
      image = img_lib.grayscale(image);
    }
    if (state.brightness != 0.0 || state.contrast != 1.0) {
      image = img_lib.adjustColor(
        image,
        brightness: (state.brightness * 100).round(),
        contrast: ((state.contrast - 1.0) * 100).round(),
      );
    }

    // Сохранение во временную директорию
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/temp_scan_page_${index}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(img_lib.encodeJpg(image));

    return tempFile;
  }

  // --- Диалоговое окно для переименования ---
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
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            ElevatedButton(
              child: const Text('Сохранить'),
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            ),
          ],
        );
      },
    );
  }



  Future<String> _saveAsImage(String fileName) async {
    if (widget.sourceFilePaths.isEmpty) {
      throw Exception("Нет исходного файла для сохранения изображения.");
    }

    File finalFileToSave;
    bool isTempFile = false;

    if (widget.editStates != null && widget.editStates!.isNotEmpty) {
      final tempFile = await _applyFiltersAndSaveTemp(widget.editStates!.first, 0);
      finalFileToSave = tempFile;
      isTempFile = true;
    } else {
      finalFileToSave = File(widget.sourceFilePaths.first);
    }

    final imageBytes = await finalFileToSave.readAsBytes();

    await ImageGallerySaverPlus.saveImage(
        imageBytes,
        name: fileName,
        quality: 100
    );

    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.jpg') ? fileName.substring(0, fileName.length - 4) : fileName;
    final internalPath = '${outputDir.path}/$baseName.jpg';

    final internalFile = File(internalPath);
    await internalFile.writeAsBytes(imageBytes);

    if (isTempFile) {
      await finalFileToSave.delete();
    }

    return internalPath;
  }

  Future<String> _saveAsPdf(String fileName) async {
    final pdf = pw.Document();

    if (widget.sourceFilePaths.isEmpty) {
      throw Exception("Нет исходных файлов для создания PDF.");
    }

    final List<File> filesToProcess = [];
    bool tempFilesCreated = false;

    try {
      if (widget.editStates != null && widget.editStates!.length == widget.sourceFilePaths.length) {
        for (int i = 0; i < widget.editStates!.length; i++) {
          final tempFile = await _applyFiltersAndSaveTemp(widget.editStates![i], i);
          filesToProcess.add(tempFile);
        }
        tempFilesCreated = true;
      } else {
        filesToProcess.addAll(widget.sourceFilePaths.map((path) => File(path)));
      }

      for (final file in filesToProcess) {
        final imageBytes = await file.readAsBytes();
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

    } finally {
      if (tempFilesCreated) {
        for (final file in filesToProcess) {
          await file.delete();
        }
      }
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.pdf') ? fileName.substring(0, fileName.length - 4) : fileName;
    final finalPath = '${outputDir.path}/$baseName.pdf';
    final file = File(finalPath);

    await file.writeAsBytes(await pdf.save());

    return file.path;
  }



  Future<void> _handleSave(SaveFormat format) async {
    String defaultName = 'Scan_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final newFileName = await _showRenameDialog(context, defaultName);

    if (!mounted) return;

    if (newFileName == null || newFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранение отменено.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    String finalPath = '';
    try {
      if (format == SaveFormat.img) {
        if (widget.sourceFilePaths.isEmpty) throw Exception("Отсутствует изображение для сохранения.");
        if (widget.editStates != null && widget.editStates!.length > 1) {
          throw Exception("IMG доступно только для одной страницы. Используйте PDF.");
        }
        finalPath = await _saveAsImage(newFileName);
      } else {
        if (widget.sourceFilePaths.isEmpty) throw Exception("Отсутствует изображение для сохранения.");
        finalPath = await _saveAsPdf(newFileName);
      }


      // Регистрируем локально и загружаем на сервер в фоне
      await DocumentRegistry().load();
      await DocumentRegistry().add(DocEntry(
        localPath: finalPath,
        remoteId: null,
        name: newFileName,
      ));

      () async {
        try {
          final remote = await DocumentSyncService()
              .upload(File(finalPath), name: newFileName);
          await DocumentRegistry().updateRemoteId(finalPath, remote.id);
        } catch (e) {
          debugPrint('Sync upload failed: $e');
        }
      }();

      setState(() {
        _isSaving = false;
        _finalPath = finalPath;
        _finalFormat = format;
      });

    } catch (e) {

      setState(() {
        _isSaving = false;
        _errorMessage = 'Ошибка сохранения: ${e.toString()}';
      });
    }
  }

  // --- UI Виджеты ---

  @override
  Widget build(BuildContext context) {
    if (_isSaving) {
      return _buildSavingInProgressScreen();
    }
    if (_finalPath != null && _finalFormat != null) {
      return _buildSaveSuccessScreen();
    }
    if (_errorMessage != null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Сохранение документа')),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _buildOptionsScreen(),
      ),
    );
  }

  Widget _buildOptionsScreen() {
    final int pageCount = widget.editStates?.length ?? widget.sourceFilePaths.length;
    final bool isMultiPage = pageCount > 1;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
              isMultiPage ? Icons.description : Icons.drive_file_rename_outline,
              color: Colors.blue,
              size: 80
          ),
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
            subText: pageCount > 0 ? '(1 фото)' : '',
            onTap: () => _handleSave(SaveFormat.img),
            enable: pageCount == 1,
          ),
          const SizedBox(height: 16),

          _buildOptionButton(
            context,
            icon: Icons.picture_as_pdf,
            text: 'Сохранить в PDF (Документ)',
            color: Colors.red,
            subText: pageCount > 0 ? '($pageCount фото)' : '',
            onTap: () => _handleSave(SaveFormat.pdf),
          ),
        ],
      ),
    );
  }


  Widget _buildSavingInProgressScreen() {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Сохранение документа...', style: TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }


  String get formatText {
    return _finalFormat == SaveFormat.pdf ? 'PDF-файл' : 'Фото/Изображение';
  }

  Widget _buildSaveSuccessScreen() {

    final String savedFormatText = formatText;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 100),
              const SizedBox(height: 20),
              const Text(
                'Документ сохранен!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$savedFormatText успешно сохранено и доступно в разделе "Мои файлы".',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {

                  Navigator.pushAndRemoveUntil(
                    context,

                    MaterialPageRoute(builder: (_) => const MainScreen()),
                        (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Перейти в "Мои файлы"',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Ошибка!')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              const Text(
                'Не удалось сохранить файл:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                },
                child: const Text('Повторить/Назад'),
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
        bool enable = true,
      }) {
    return ElevatedButton(
      onPressed: enable ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enable ? color : Colors.grey.shade400,
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
