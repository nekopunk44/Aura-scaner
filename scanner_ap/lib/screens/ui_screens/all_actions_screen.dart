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
import '../../services/premium_service.dart';
import 'premium_screen.dart';
import 'add_password_screen.dart';
import 'restore_photo_screen.dart';
import 'highlight_screen.dart';
import 'document_ai_screen.dart';
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
import 'voice_note_screen.dart';
import 'print_screen.dart';
import 'remove_watermark_screen.dart';
import 'hot_zone_screen.dart';

const _documentKey = 'saved_document_paths';

class AllActionsScreen extends StatelessWidget {
  final VoidCallback? onDocumentImported;

  const AllActionsScreen({super.key, this.onDocumentImported});

  void _showPremiumPaywall(BuildContext context, String featureName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.workspace_premium, size: 32, color: Colors.amber.shade600),
            ),
            const SizedBox(height: 16),
            Text(
              'Функция только для Premium',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              '«$featureName» доступна в подписке.\nОформите Premium чтобы разблокировать её.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: subColor, height: 1.45),
            ),
            const SizedBox(height: 24),
            _PremiumBenefitRow(icon: Icons.library_books, label: 'Пакетное сканирование (+10 страниц)', isDark: isDark),
            _PremiumBenefitRow(icon: Icons.auto_fix_high, label: 'Восстановление фото и выделение текста', isDark: isDark),
            _PremiumBenefitRow(icon: Icons.lock, label: 'Защита паролем и удаление водяных знаков', isDark: isDark),
            _PremiumBenefitRow(icon: Icons.voice_chat, label: 'Голосовые заметки и Эко-сканер', isDark: isDark, isLast: true),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
                child: const Text('Оформить Premium',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Не сейчас', style: TextStyle(color: subColor, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
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
    final effectiveTap = (isPremium && !PremiumService().isPremium)
        ? () => _showPremiumPaywall(context, title)
        : onTap ?? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('«$title» в разработке')),
            );

    return buildFeatureTile(
      context,
      title: title,
      icon: icon,
      onTap: effectiveTap,
      isPremium: isPremium,
      subtitle: subtitle,
      iconColor: iconColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final accentColor = isDark
        ? const Color(0xFF2CA5E0)
        : const Color(0xFF2CA5E0).withValues(alpha: 0.8);

    Widget buildSectionHeader(String title, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(icon, size: 18, color: accentColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: titleColor,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSectionHeader('Сканировать', Icons.camera_alt_outlined),

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

          buildSectionHeader('Редактировать', Icons.tune),

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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => RestorePhotoScreen(onSaved: onDocumentImported),
                  )),
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => HighlightScreen(onSaved: onDocumentImported),
                  )),
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

          buildSectionHeader('Делиться', Icons.ios_share_outlined),

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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => AddPasswordScreen(onSaved: onDocumentImported),
                  )),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Печать',
                  Icons.print,
                  subtitle: 'Распечатайте документ',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const PrintScreen(),
                  )),
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
                  Icons.auto_fix_normal,
                  isPremium: true,
                  subtitle: 'Выделите и сотрите водяной знак',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => RemoveWatermarkScreen(onSaved: onDocumentImported),
                  )),
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

          buildSectionHeader('Импорты', Icons.file_download_outlined),

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

          buildSectionHeader('AI-инструменты', Icons.auto_awesome_outlined),

          Row(
            children: [
              Expanded(
                child: buildTile(
                  context,
                  'Извлекает суть и действия',
                  Icons.mobile_friendly,
                  subtitle: 'Для договора - выделяет ключевые моменты',
                  iconColor: Colors.red.shade700,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DocumentAiScreen.analyze(),
                  )),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Наведите камеру на документ',
                  Icons.camera_alt,
                  subtitle: 'Сфотографируйте — ИИ мгновенно выделит суть',
                  iconColor: Colors.green.shade700,
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DocumentAiScreen.camera(),
                  )),
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => VoiceNoteScreen(onSaved: onDocumentImported),
                  )),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: buildTile(
                  context,
                  'Горячая зона',
                  Icons.hot_tub,
                  subtitle: 'Нажав на подпись, вы увидите визитку человека',
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const HotZoneScreen(),
                  )),
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
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DocumentAiScreen.eco(),
                  )),
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

class _PremiumBenefitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isLast;

  const _PremiumBenefitRow({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: Colors.amber.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF3A4558),
                  ),
                ),
              ),
              Icon(Icons.check, size: 16, color: Colors.green.shade400),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: dividerColor),
      ],
    );
  }
}
