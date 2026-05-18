import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'camera.dart';
import 'ui_helpers.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import 'qr_code_scanner/qr_code.dart';
import 'ocr/ocr_screen.dart';
import 'merge/merge_documents_screen.dart';
import 'signature/home_screen.dart' as sig;
import 'color_adjustment_screen.dart';
import 'remove_spots_screen.dart';
import 'reorder_pdf_pages_screen.dart';
import 'compress_pdf_screen.dart';
import 'extract_pdf_pages_screen.dart';

const _documentKey = 'saved_document_paths';

class AllActionsScreen extends StatelessWidget {
  final VoidCallback? onDocumentImported;

  const AllActionsScreen({super.key, this.onDocumentImported});

  void _handleAction(
      BuildContext context,
      String featureName, {
        bool isPremium = false,
      }) {
    if (isPremium) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Для функции "$featureName" требуется Премиум.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Запуск функции: $featureName')));
    }
  }

  Widget buildTile(
      BuildContext context,
      String title,
      IconData icon, {
        bool isPremium = false,
        String? subtitle,
        VoidCallback? onTap,
        Color iconColor = Colors.blue,
      }) {
    return buildFeatureTile(
      context,
      title: title,
      icon: icon,
      onTap: onTap ?? () => _handleAction(context, title, isPremium: isPremium),
      isPremium: isPremium,
      subtitle: subtitle,
      iconColor: iconColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget buildSectionHeader(String title) {
      return Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader('СКАНИРОВАТЬ'),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Документ',
                  Icons.description,
                  iconColor: Colors.purple,
                  subtitle: 'Сканирование нескольких листов',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(initialFeature: 'Документ'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Удостоверение личности',
                  Icons.add_card,
                  subtitle: 'Снимок обоих сторон',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(initialFeature: 'Удостоверение личности'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Паспорт',
                  Icons.man,
                  subtitle: 'Сканирование страниц данных',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(initialFeature: 'Паспорт'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  '+10 страниц',
                  Icons.library_books,
                  isPremium: true,
                  subtitle: 'Сканирование в пакетном режиме',
                  iconColor: Colors.black,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(initialFeature: '+10 страниц'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Перевод',
                  Icons.translate,
                  isPremium: false,
                  subtitle: 'Мгновенный перевод текста',
                  iconColor: Colors.black,
                  onTap: () async {
                    await availableCameras();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CameraScreen(initialFeature: 'Перевод'),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Сканер qr-код',
                  Icons.qr_code_2,
                  isPremium: false,
                  subtitle: 'Мгновенный сканер qr-кода',
                  iconColor: Colors.teal,
                  onTap: () async {
                    await availableCameras();
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QrCodeScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          buildSectionHeader('РЕДАКТИРОВАТЬ'),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Изменение цвета',
                  Icons.color_lens,
                  iconColor: Colors.red,
                  subtitle: 'Цвет бумаги, букв',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ColorAdjustmentScreen(
                        onImageSaved: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Местоположение и время',
                  Icons.punch_clock_rounded,
                  subtitle: 'Геолокация и время',
                  onTap: () => _addTimestamp(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Обрезать, повернуть',
                  Icons.crop,
                  subtitle: 'Изменение соотношения сторон, 90° / 180° градусов',
                  onTap: () => _cropAndRotate(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Знак (подпись)',
                  Icons.edit_note,
                  iconColor: Colors.green,
                  subtitle: 'Рисование подписи',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const sig.HomeScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Восстановить фото',
                  Icons.auto_fix_high,
                  isPremium: true,
                  subtitle: 'Улучшение качества и четкости',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Убрать метки/пятна',
                  Icons.layers_clear,
                  subtitle: 'Удаление дефектов документа',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RemoveSpotsScreen(
                        onImageSaved: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Объединить файлы',
                  Icons.merge_type,
                  iconColor: Colors.purple,
                  subtitle: 'PDF и изображения в один PDF',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MergeDocumentsScreen(
                        onMergeComplete: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Извлечь страницы PDF',
                  Icons.auto_delete,
                  isPremium: false,
                  subtitle: 'Извлечение отдельных страниц',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExtractPdfPagesScreen(
                        onPdfSaved: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'OCR',
                  Icons.text_fields_outlined,
                  iconColor: Colors.black45,
                  subtitle: 'Извлечение текста из файла + копирование',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OcrScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Сжать PDF',
                  Icons.leak_remove_sharp,
                  isPremium: false,
                  subtitle: 'Сжатие документа PDF',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompressPdfScreen(
                        onPdfSaved: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Выделять',
                  Icons.auto_fix_high,
                  isPremium: true,
                  subtitle: 'Подсветка важного текста',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Изменение порядка страниц',
                  Icons.layers_clear,
                  subtitle: 'Редактирование порядка страниц',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReorderPdfPagesScreen(
                        onPdfSaved: onDocumentImported,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          buildSectionHeader('ДЕЛИТЬСЯ'),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Конвертировать в PDF',
                  Icons.picture_as_pdf,
                  subtitle: 'Изображения → один PDF',
                  iconColor: Colors.red.shade700,
                  onTap: () => _convertToPdf(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Конвертировать в JPEG',
                  Icons.image,
                  subtitle: 'PDF страницы → изображения',
                  iconColor: Colors.green.shade700,
                  onTap: () => _convertToJpeg(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Добавить пароль',
                  Icons.lock,
                  subtitle: 'Защитите свой документ',
                  isPremium: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Печать',
                  Icons.print,
                  subtitle: 'Распечатайте документ',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Удалить водяной знак',
                  Icons.close,
                  isPremium: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Электронная почта',
                  Icons.mail_outline,
                  subtitle: 'Отправить файл по почте',
                  onTap: () => _shareByEmail(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          buildSectionHeader('Импорты'),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Импорт документов',
                  Icons.file_download,
                  subtitle: 'Импорт файлов',
                  iconColor: Colors.greenAccent,
                  onTap: () {
                    _showImportOptions(context);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Импорт изображений',
                  Icons.image,
                  subtitle: 'Импорт фото',
                  iconColor: Colors.blueAccent,
                  onTap: () {
                    _importImage(context);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          buildSectionHeader('ИИ'),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Извлекает суть и действия',
                  Icons.mobile_friendly,
                  subtitle: 'Для договора - выделяет ключевые моменты',
                  iconColor: Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Наведите камеру на документ',
                  Icons.cabin,
                  subtitle: 'Покажет уведомление ("Эту квитанцию нужно оплатить до завтра")',
                  iconColor: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Голосовая заметка',
                  Icons.voice_chat,
                  subtitle: 'Можете оставить голосовой комментарий прямо в конкретном пункте документа',
                  isPremium: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Горячая зона',
                  Icons.hot_tub,
                  subtitle: 'Нажав на подпись, вы увидите визитку человека',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Эко упаковка',
                  Icons.eco,
                  subtitle: 'Рассказывает про упаковку',
                  isPremium: true,
                  iconColor: Colors.green.shade500,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Импортировать документ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF документ'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSaveFile(context, extensions: ['pdf']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.blue),
              title: const Text('Word / TXT'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSaveFile(context, extensions: ['docx', 'doc', 'txt']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.orange),
              title: const Text('Любой файл'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSaveFile(context, extensions: null);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSaveFile(
    BuildContext context, {
    required List<String>? extensions,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: extensions != null ? FileType.custom : FileType.any,
      allowedExtensions: extensions,
      allowMultiple: false,
    );
    if (result == null || result.files.first.path == null) return;

    final srcPath = result.files.first.path!;
    final fileName = p.basename(srcPath);

    try {
      final dir = await getApplicationDocumentsDirectory();
      final destPath = '${dir.path}/$fileName';
      if (srcPath != destPath) {
        await File(srcPath).copy(destPath);
      }

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(destPath)) {
        paths.add(destPath);
        await prefs.setStringList(_documentKey, paths);
      }

      onDocumentImported?.call();
      messenger.showSnackBar(
        SnackBar(content: Text('Импортировано: $fileName')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  Future<void> _cropAndRotate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезать / Повернуть',
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final ext = p.extension(cropped.path).isEmpty ? '.jpg' : p.extension(cropped.path);
    final fileName = 'cropped_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = '${dir.path}/$fileName';
    await File(cropped.path).copy(destPath);

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_documentKey) ?? [];
    if (!paths.contains(destPath)) {
      paths.add(destPath);
      await prefs.setStringList(_documentKey, paths);
    }
    onDocumentImported?.call();
    messenger.showSnackBar(SnackBar(content: Text('Сохранено: $fileName')));
  }

  Future<void> _addTimestamp(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await File(picked.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final srcImage = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, srcImage.width.toDouble(), srcImage.height.toDouble()),
    );
    canvas.drawImage(srcImage, Offset.zero, Paint());

    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}'
        '  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final fontSize = (srcImage.width * 0.04).clamp(14.0, 48.0);

    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: fontSize,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: fontSize,
        background: Paint()..color = const Color(0xAA000000),
      ))
      ..addText('  $stamp  ');
    final paragraph = pb.build()
      ..layout(ui.ParagraphConstraints(width: srcImage.width.toDouble()));
    canvas.drawParagraph(
      paragraph,
      Offset(10, srcImage.height - paragraph.height - 10),
    );

    final picture = recorder.endRecording();
    final result = await picture.toImage(srcImage.width, srcImage.height);
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'timestamped_${DateTime.now().millisecondsSinceEpoch}.png';
    final destPath = '${dir.path}/$fileName';
    await File(destPath).writeAsBytes(byteData.buffer.asUint8List());

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_documentKey) ?? [];
    if (!paths.contains(destPath)) {
      paths.add(destPath);
      await prefs.setStringList(_documentKey, paths);
    }
    onDocumentImported?.call();
    messenger.showSnackBar(SnackBar(content: Text('Сохранено с меткой: $fileName')));
  }

  Future<void> _convertToPdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Конвертация...'),
          ]),
        ),
      );
    }

    try {
      final doc = pw.Document();
      for (final file in result.files) {
        if (file.path == null) continue;
        final bytes = await File(file.path!).readAsBytes();
        final decoded = img.decodeImage(bytes);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(
            decoded?.width.toDouble() ?? 595,
            decoded?.height.toDouble() ?? 842,
          ),
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
        ));
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'converted_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = '${dir.path}/$fileName';
      await File(outputPath).writeAsBytes(await doc.save());

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(outputPath)) {
        paths.add(outputPath);
        await prefs.setStringList(_documentKey, paths);
      }
      onDocumentImported?.call();

      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('PDF создан: $fileName'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _convertToJpeg(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result == null || result.files.first.path == null) return;

    final pdfPath = result.files.first.path!;
    final baseName = p.basenameWithoutExtension(pdfPath);

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Конвертация...'),
          ]),
        ),
      );
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final pdfDoc = await PdfDocument.openFile(pdfPath);
      int saved = 0;

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];

      try {
        for (int i = 0; i < pdfDoc.pages.length; i++) {
          final page = pdfDoc.pages[i];
          final pdfImage = await page.render(
            fullWidth: page.width * 2,
            fullHeight: page.height * 2,
          );
          if (pdfImage == null) continue;
          try {
            final imgImage = img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              order: img.ChannelOrder.bgra,
            );
            final jpegBytes = Uint8List.fromList(img.encodeJpg(imgImage, quality: 90));
            final fileName = '${baseName}_page${i + 1}.jpg';
            final outputPath = '${dir.path}/$fileName';
            await File(outputPath).writeAsBytes(jpegBytes);
            if (!paths.contains(outputPath)) paths.add(outputPath);
            saved++;
          } finally {
            pdfImage.dispose();
          }
        }
      } finally {
        await pdfDoc.dispose();
      }

      await prefs.setStringList(_documentKey, paths);
      onDocumentImported?.call();

      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Сохранено $saved изображений'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _shareByEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.first.path == null) return;

    final path = result.files.first.path!;
    if (!await File(path).exists()) {
      messenger.showSnackBar(const SnackBar(content: Text('Файл не найден')));
      return;
    }
    await Share.shareXFiles([XFile(path)], subject: p.basename(path));
  }

  Future<void> _importImage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = p.basename(file.path);
      final destPath = '${dir.path}/$fileName';
      if (file.path != destPath) {
        await File(file.path).copy(destPath);
      }

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(destPath)) {
        paths.add(destPath);
        await prefs.setStringList(_documentKey, paths);
      }

      onDocumentImported?.call();
      messenger.showSnackBar(
        SnackBar(content: Text('Изображение импортировано: $fileName')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }
}
