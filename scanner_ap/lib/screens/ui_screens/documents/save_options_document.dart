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
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../../utils/pptx_builder.dart';
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
  String? _progressMessage; // например «Распознаём текст 2/10»


  Future<File> _applyFiltersAndSaveTemp(ImageEditState state, int index) async {
    final originalFile = File(state.path);
    final imageBytes = await originalFile.readAsBytes();

    img_lib.Image? image = img_lib.decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Не удалось декодировать изображение для страницы ${index + 1}');
    }

    // Поворот.
    if (state.rotation != 0.0) {
      final int angle = state.rotation.round();
      if (angle == 90 || angle == 180 || angle == 270) {
        image = img_lib.copyRotate(image, angle: angle);
      }
    }
    // WYSIWYG: повторяем формулу превью (_getColorFilter). При Ч/Б превью
    // показывает ТОЛЬКО оттенки серого (яркость/контраст не применяет), иначе
    // out = contrast*канал + brightness*255 (ColorFilter.matrix).
    if (state.isGrayScale) {
      image = img_lib.grayscale(image);
    } else if (state.brightness != 0.0 || state.contrast != 1.0) {
      final double c = state.contrast;
      final double off = state.brightness * 255.0;
      for (final p in image) {
        p
          ..r = (c * p.r + off).clamp(0, 255)
          ..g = (c * p.g + off).clamp(0, 255)
          ..b = (c * p.b + off).clamp(0, 255);
      }
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
        // Размер страницы = пропорции скана → без белых полей A4, край-в-край.
        final double w = (pdfImage.width ?? 1000).toDouble();
        final double h = (pdfImage.height ?? 1414).toDouble();
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(w, h),
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Image(pdfImage, fit: pw.BoxFit.contain);
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

  /// Searchable PDF: страница = скан-картинка (точная вёрстка оригинала), а
  /// поверх — НЕВИДИМЫЙ текст по координатам слов из Tesseract hOCR. Выглядит
  /// пиксель-в-пиксель как оригинал, но текст выделяется/ищется/копируется.
  Future<String> _saveAsTextPdf(String fileName) async {
    if (widget.sourceFilePaths.isEmpty) {
      throw Exception("Нет страниц для распознавания.");
    }
    final l10n = AppLocalizations.of(context);
    final int total = widget.sourceFilePaths.length;
    final font = await PdfGoogleFonts.robotoRegular();
    final doc = pw.Document();
    final tempFiles = <File>[];

    try {
      for (int i = 0; i < total; i++) {
        if (mounted) {
          setState(
            () => _progressMessage = '${l10n.docOcrInProgress} ${i + 1}/$total',
          );
        }
        // Страница-картинка: применённые фильтры (как видел пользователь).
        File pageFile;
        if (widget.editStates != null && widget.editStates!.length == total) {
          pageFile = await _applyFiltersAndSaveTemp(widget.editStates![i], i);
          tempFiles.add(pageFile);
        } else {
          pageFile = File(widget.sourceFilePaths[i]);
        }

        final bytes = await pageFile.readAsBytes();
        final decoded = img_lib.decodeImage(bytes);
        final double imgW = (decoded?.width ?? 1000).toDouble();
        final double imgH = (decoded?.height ?? 1414).toDouble();

        // hOCR (rus+eng) — слова + их рамки в пикселях изображения.
        List<_HocrWord> words = const [];
        try {
          final hocr = await FlutterTesseractOcr.extractHocr(
            pageFile.path,
            language: 'rus+eng',
          );
          words = _parseHocr(hocr);
        } catch (_) {
          // Без hOCR страница останется картинкой без текстового слоя.
        }

        final pdfImage = pw.MemoryImage(bytes);
        final double pageW = PdfPageFormat.a4.width;
        final double scale = pageW / imgW;
        final double pageH = imgH * scale;

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(pageW, pageH),
            margin: pw.EdgeInsets.zero,
            build: (context) => pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
                ),
                for (final w in words)
                  pw.Positioned(
                    left: w.x0 * scale,
                    top: w.y0 * scale,
                    child: pw.Text(
                      w.text,
                      style: pw.TextStyle(
                        font: font,
                        fontSize: ((w.y1 - w.y0) * scale).clamp(4.0, 40.0),
                        // Прозрачный текст: невидим, но выделяется/ищется.
                        color: const PdfColor(0, 0, 0, 0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    } finally {
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final baseName = fileName.endsWith('.pdf')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final finalPath = '${outputDir.path}/$baseName.pdf';
    await File(finalPath).writeAsBytes(await doc.save());
    return finalPath;
  }

  /// Парсит hOCR Tesseract → слова с рамками (bbox в пикселях изображения).
  List<_HocrWord> _parseHocr(String hocr) {
    final re = RegExp(
      r'''class=['"]ocrx_word['"][^>]*?title=['"]bbox (\d+) (\d+) (\d+) (\d+)[^'"]*['"][^>]*>(.*?)</span>''',
      dotAll: true,
    );
    final words = <_HocrWord>[];
    for (final m in re.allMatches(hocr)) {
      final text = _unescapeHtml(
        m.group(5)!.replaceAll(RegExp(r'<[^>]*>'), ''),
      ).trim();
      if (text.isEmpty) continue;
      words.add(_HocrWord(
        double.parse(m.group(1)!),
        double.parse(m.group(2)!),
        double.parse(m.group(3)!),
        double.parse(m.group(4)!),
        text,
      ));
    }
    return words;
  }

  String _unescapeHtml(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");

  /// Возвращает файлы страниц с применёнными фильтрами редактора
  /// (или исходники, если фильтров нет). tempFiles — созданные временные
  /// файлы, их нужно удалить после использования.
  Future<(List<File>, List<File>)> _resolvePageFiles() async {
    final files = <File>[];
    final tempFiles = <File>[];
    final total = widget.sourceFilePaths.length;
    if (widget.editStates != null && widget.editStates!.length == total) {
      for (int i = 0; i < total; i++) {
        final f = await _applyFiltersAndSaveTemp(widget.editStates![i], i);
        files.add(f);
        tempFiles.add(f);
      }
    } else {
      files.addAll(widget.sourceFilePaths.map(File.new));
    }
    return (files, tempFiles);
  }

  /// Excel: каждая страница распознаётся Tesseract'ом (rus+eng), строки
  /// текста становятся строками таблицы. Колонки — по табам/2+ пробелам
  /// (простая табличная эвристика). Каждая страница — отдельный лист.
  Future<String> _saveAsXlsx(String fileName) async {
    final l10n = AppLocalizations.of(context);
    final (files, tempFiles) = await _resolvePageFiles();
    final workbook = xlsio.Workbook();

    try {
      for (int i = 0; i < files.length; i++) {
        if (mounted) {
          setState(
            () => _progressMessage =
                '${l10n.docOcrInProgress} ${i + 1}/${files.length}',
          );
        }

        final sheet = i == 0
            ? workbook.worksheets[0]
            : workbook.worksheets.add();
        sheet.name = 'Page ${i + 1}';

        String text = '';
        try {
          text = await FlutterTesseractOcr.extractText(
            files[i].path,
            language: 'rus+eng',
          );
        } catch (_) {
          // Страница без распознанного текста останется пустым листом.
        }

        final lines = text
            .split('\n')
            .map((l) => l.trimRight())
            .where((l) => l.trim().isNotEmpty)
            .toList();

        for (int row = 0; row < lines.length; row++) {
          // Табличная эвристика: таб или 2+ пробела = граница колонки.
          final cells = lines[row].split(RegExp(r'\t| {2,}'));
          for (int col = 0; col < cells.length; col++) {
            final value = cells[col].trim();
            if (value.isEmpty) continue;
            final range = sheet.getRangeByIndex(row + 1, col + 1);
            final asNum = num.tryParse(value.replaceAll(',', '.'));
            if (asNum != null) {
              range.setNumber(asNum.toDouble());
            } else {
              range.setText(value);
            }
          }
        }
        // Автоширина первых колонок, чтобы текст не сжимался в узкие ячейки.
        for (int col = 1; col <= 8; col++) {
          sheet.autoFitColumn(col);
        }
      }

      final bytes = workbook.saveAsStream();
      final outputDir = await getApplicationDocumentsDirectory();
      final baseName = fileName.toLowerCase().endsWith('.xlsx')
          ? fileName.substring(0, fileName.length - 5)
          : fileName;
      final finalPath = '${outputDir.path}/$baseName.xlsx';
      await File(finalPath).writeAsBytes(bytes, flush: true);
      return finalPath;
    } finally {
      workbook.dispose();
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// PowerPoint: одна страница скана = один слайд 16:9 (картинка вписана
  /// по центру). Генерация OOXML — см. PptxBuilder.
  Future<String> _saveAsPptx(String fileName) async {
    final (files, tempFiles) = await _resolvePageFiles();
    try {
      final outputDir = await getApplicationDocumentsDirectory();
      final baseName = fileName.toLowerCase().endsWith('.pptx')
          ? fileName.substring(0, fileName.length - 5)
          : fileName;
      final finalPath = '${outputDir.path}/$baseName.pptx';
      await PptxBuilder.build(
        imagePaths: files.map((f) => f.path).toList(),
        outputPath: finalPath,
      );
      return finalPath;
    } finally {
      for (final f in tempFiles) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
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
      _progressMessage = null;
    });

    String finalPath = '';
    try {
      if (widget.sourceFilePaths.isEmpty) {
        throw Exception("Отсутствует изображение для сохранения.");
      }
      if (format == SaveFormat.img) {
        if (widget.editStates != null && widget.editStates!.length > 1) {
          throw Exception("IMG доступно только для одной страницы. Используйте PDF.");
        }
        finalPath = await _saveAsImage(newFileName);
      } else if (format == SaveFormat.textPdf) {
        finalPath = await _saveAsTextPdf(newFileName);
      } else if (format == SaveFormat.xlsx) {
        finalPath = await _saveAsXlsx(newFileName);
      } else if (format == SaveFormat.pptx) {
        finalPath = await _saveAsPptx(newFileName);
      } else {
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
          const SizedBox(height: 14),
          _buildOptionButton(
            context,
            icon: Icons.text_snippet_outlined,
            text: l10n.saveAsTextPdf,
            color: const Color(0xFF22C55E),
            subText: '(OCR)',
            onTap: () => _handleSave(SaveFormat.textPdf),
          ),
          const SizedBox(height: 14),
          _buildOptionButton(
            context,
            icon: Icons.table_chart_outlined,
            text: l10n.saveAsExcel,
            color: const Color(0xFF107C41),
            subText: '(XLSX, OCR)',
            onTap: () => _handleSave(SaveFormat.xlsx),
          ),
          const SizedBox(height: 14),
          _buildOptionButton(
            context,
            icon: Icons.slideshow_outlined,
            text: l10n.saveAsPowerPoint,
            color: const Color(0xFFC43E1C),
            subText: '(PPTX)',
            onTap: () => _handleSave(SaveFormat.pptx),
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
            Text(_progressMessage ?? l10n.savingInProgress,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: subColor)),
          ],
        ),
      ),
    );
  }

  String _formatText(AppLocalizations l10n) {
    return switch (_finalFormat) {
      SaveFormat.img => l10n.saveFormatImage,
      SaveFormat.xlsx => 'Excel (XLSX)',
      SaveFormat.pptx => 'PowerPoint (PPTX)',
      _ => l10n.saveFormatPdf,
    };
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

/// Слово из hOCR Tesseract: рамка (bbox в пикселях изображения) + текст.
class _HocrWord {
  final double x0;
  final double y0;
  final double x1;
  final double y1;
  final String text;
  const _HocrWord(this.x0, this.y0, this.x1, this.y1, this.text);
}
