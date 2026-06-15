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
import '../../../l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image/image.dart' as img_lib;
import 'document_camera_edit.dart';
import '../main_screen/app_tabs_screen.dart';
import '../../../services/document_sync_service.dart';
import '../../../services/document_registry.dart';
import '../../../models/save_format.dart';

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
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: currentFileName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogBg,
        title: Text(l10n.fileNameTitle, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: l10n.fileNameTitle,
            labelStyle: TextStyle(color: subColor),
            hintText: l10n.fileNameHint,
            hintStyle: TextStyle(color: subColor),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFE8EDF5))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2CA5E0))),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(null),
            child: Text(l10n.actionCancel, style: TextStyle(color: subColor)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2CA5E0), foregroundColor: Colors.white, elevation: 0),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
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
    final l10n = AppLocalizations.of(context);
    String defaultName = 'Scan_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
    final newFileName = await _showRenameDialog(context, defaultName);

    if (!mounted) return;

    if (newFileName == null || newFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.docSaveCancelled)),
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
        _errorMessage = l10n.saveErrorDetail(e.toString());
      });
    }
  }

  // --- UI Виджеты ---

  @override
  Widget build(BuildContext context) {
    if (_isSaving) return _buildSavingInProgressScreen(context);
    if (_finalPath != null && _finalFormat != null) return _buildSaveSuccessScreen(context);
    if (_errorMessage != null) return _buildErrorScreen(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.saveDocumentTitle, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: SafeArea(child: _buildOptionsScreen(context)),
    );
  }

  Widget _buildOptionsScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final int pageCount = widget.editStates?.length ?? widget.sourceFilePaths.length;
    final bool isMultiPage = pageCount > 1;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            isMultiPage ? Icons.description : Icons.drive_file_rename_outline,
            color: const Color(0xFF2CA5E0),
            size: 72,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.saveFmtTitle,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.savePageCount(pageCount),
            style: TextStyle(fontSize: 14, color: subColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          _buildOptionButton(
            context,
            icon: Icons.image_outlined,
            text: l10n.saveAsImage,
            color: const Color(0xFF2CA5E0),
            subText: '(JPG)',
            onTap: () => _handleSave(SaveFormat.img),
            enable: pageCount == 1,
          ),
          const SizedBox(height: 14),
          _buildOptionButton(
            context,
            icon: Icons.picture_as_pdf,
            text: l10n.saveAsPdf,
            color: Colors.red.shade600,
            subText: '($pageCount стр.)',
            onTap: () => _handleSave(SaveFormat.pdf),
          ),
        ],
      ),
    );
  }

  Widget _buildSavingInProgressScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF2CA5E0)),
            const SizedBox(height: 20),
            Text(l10n.savingInProgress, style: TextStyle(fontSize: 16, color: subColor)),
          ],
        ),
      ),
    );
  }

  String _formatText(AppLocalizations l10n) {
    return _finalFormat == SaveFormat.pdf ? l10n.saveFormatPdf : l10n.saveFormatImage;
  }

  Widget _buildSaveSuccessScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96, height: 96,
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.green, size: 52),
              ),
              const SizedBox(height: 24),
              Text(l10n.saveDocSaved,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.saveSuccessBody(_formatText(l10n)),
                style: TextStyle(fontSize: 15, color: subColor, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                    (route) => false,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2CA5E0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l10n.saveGoToMyFiles, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.commonError, style: TextStyle(color: textColor)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 72),
              const SizedBox(height: 20),
              Text(l10n.saveFailedLabel, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor)),
              const SizedBox(height: 10),
              Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade400, fontSize: 14)),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => setState(() => _errorMessage = null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2CA5E0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.actionRetry),
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
    final effectiveColor = enable ? color : color.withValues(alpha: 0.4);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enable ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: effectiveColor,
          disabledBackgroundColor: effectiveColor,
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
              child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            ),
            if (subText.isNotEmpty)
              Text(subText, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
