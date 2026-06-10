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

class AllActionsScreen extends StatefulWidget {
  final VoidCallback? onDocumentImported;

  const AllActionsScreen({super.key, this.onDocumentImported});

  @override
  State<AllActionsScreen> createState() => _AllActionsScreenState();
}

class _AllActionsScreenState extends State<AllActionsScreen>
    with TickerProviderStateMixin {
  static const _categories = [
    ('Скан', Icons.camera_alt_outlined),
    ('Правка', Icons.tune),
    ('Поделиться', Icons.ios_share_outlined),
    ('Импорт', Icons.file_download_outlined),
    ('AI', Icons.auto_awesome_outlined),
  ];

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

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

  Widget _tile(
    String title,
    IconData icon, {
    bool isPremium = false,
    String? subtitle,
    VoidCallback? onTap,
    Color iconColor = const Color(0xFF2CA5E0),
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

  /// Широкая карточка-«хедлайнер» — стоит первой в каждой вкладке.
  /// Горизонтальный layout (иконка крупнее, текст рядом, стрелка-CTA)
  /// выделяет флагман категории, не сливаясь с 2-колоночным grid'ом.
  Widget _wideTile(
    String title,
    IconData icon, {
    bool isPremium = false,
    String? subtitle,
    VoidCallback? onTap,
    Color iconColor = const Color(0xFF2CA5E0),
  }) {
    final effectiveTap = (isPremium && !PremiumService().isPremium)
        ? () => _showPremiumPaywall(context, title)
        : onTap ?? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('«$title» в разработке')),
            );

    return buildFeatureTileWide(
      context,
      title: title,
      icon: icon,
      onTap: effectiveTap,
      isPremium: isPremium,
      subtitle: subtitle,
      iconColor: iconColor,
    );
  }

  /// Большая карточка-«фичеред» во всю ширину. Привлекает внимание к
  /// флагманской функции категории; визуально разбивает однообразие
  /// 2-колоночного grid'а.
  Widget _featuredTile(
    String title,
    String subtitle,
    IconData icon, {
    required VoidCallback onTap,
    required List<Color> gradient,
    bool isPremium = false,
  }) {
    final effectiveTap = (isPremium && !PremiumService().isPremium)
        ? () => _showPremiumPaywall(context, title)
        : onTap;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: effectiveTap,
        splashColor: Colors.white.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pairRow(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _singleRow(Widget child) {
    return Row(
      children: [
        Expanded(child: child),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final tabBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final tabActive = const Color(0xFF2CA5E0);
    final tabInactive = isDark ? Colors.white54 : const Color(0xFF8A94A6);

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      color: bg,
      child: Column(
        children: [
          // Featured banner — флагманская AI-фича. На landscape прячем,
          // потому что высота сильно ограничена и banner+tabs+content
          // не помещаются без скролла; иконка в табах сама направит.
          if (!isLandscape) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _featuredTile(
                    'AI-анализ документа',
                    'Сфотографируйте и получите ключевые тезисы за 10 секунд',
                    Icons.auto_awesome,
                    gradient: const [
                      Color(0xFF6FCFF5),
                      Color(0xFF2CA5E0),
                      Color(0xFF1565C0)
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DocumentAiScreen.camera()),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 12),

          // Sticky tab bar категорий — на широком экране ограничен по
          // ширине и центрирован, чтобы pill-табы не растягивались
          // и капчура с активной заливкой выглядела пропорционально.
          Center(
            child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            constraints: const BoxConstraints(maxWidth: 560),
            decoration: BoxDecoration(
              color: tabBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: tabInactive,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: tabActive,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorPadding: const EdgeInsets.all(6),
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              padding: const EdgeInsets.all(4),
              tabs: [
                for (final (label, icon) in _categories)
                  Tab(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 16),
                          const SizedBox(width: 6),
                          Text(label),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 14),

          // Контент: TabBarView со списком инструментов для каждой
          // категории. Asymmetric: первая карточка в каждой вкладке —
          // во всю ширину (выделенная), остальные — по 2 в ряд.
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildScanTab(),
                _buildEditTab(),
                _buildShareTab(),
                _buildImportTab(),
                _buildAiTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Категории
  // ------------------------------------------------------------------

  Widget _buildScanTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          'Документ',
          Icons.description,
          iconColor: Colors.purple,
          subtitle: 'Сканирование нескольких листов',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraScreen(initialFeature: 'Документ'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Удостоверение',
            Icons.add_card,
            subtitle: 'Снимок обоих сторон',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CameraScreen(initialFeature: 'Удостоверение личности'),
              ),
            ),
          ),
          _tile(
            'Паспорт',
            Icons.man,
            subtitle: 'Сканирование страниц данных',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraScreen(initialFeature: 'Паспорт')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            '+10 страниц',
            Icons.library_books,
            isPremium: true,
            subtitle: 'Пакетный режим',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CameraScreen(initialFeature: '+10 страниц')),
            ),
          ),
          _tile(
            'Перевод',
            Icons.translate,
            subtitle: 'Мгновенный перевод текста',
            iconColor: const Color(0xFFE67E22),
            onTap: () async {
              await availableCameras();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CameraScreen(initialFeature: 'Перевод')),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _singleRow(
          _tile(
            'QR-код',
            Icons.qr_code_2,
            subtitle: 'Мгновенный сканер',
            iconColor: Colors.teal,
            onTap: () async {
              await availableCameras();
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QrCodeScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEditTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          'Изменение цвета',
          Icons.color_lens,
          iconColor: Colors.red,
          subtitle: 'Яркость, контраст, оттенок документа',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ColorAdjustmentScreen(
                onImageSaved: widget.onDocumentImported,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Обрезать, повернуть',
            Icons.crop,
            subtitle: '90° / 180° или произвольно',
            onTap: () => _cropAndRotate(context),
          ),
          _tile(
            'Подпись',
            Icons.edit_note,
            iconColor: Colors.green,
            subtitle: 'Рисование подписи',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const sig.HomeScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Восстановить фото',
            Icons.auto_fix_high,
            isPremium: true,
            subtitle: 'Улучшение качества',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => RestorePhotoScreen(onSaved: widget.onDocumentImported),
            )),
          ),
          _tile(
            'Убрать пятна',
            Icons.layers_clear,
            subtitle: 'Удаление дефектов',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RemoveSpotsScreen(
                  onImageSaved: widget.onDocumentImported,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Объединить файлы',
            Icons.merge_type,
            iconColor: Colors.purple,
            subtitle: 'PDF и изображения в один PDF',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MergeDocumentsScreen(
                  onMergeComplete: widget.onDocumentImported,
                ),
              ),
            ),
          ),
          _tile(
            'Извлечь страницы',
            Icons.auto_delete,
            subtitle: 'Отдельные страницы из PDF',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExtractPdfPagesScreen(
                  onPdfSaved: widget.onDocumentImported,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'OCR',
            Icons.text_fields_outlined,
            iconColor: const Color(0xFF6B7A99),
            subtitle: 'Текст из файла + копирование',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OcrScreen()),
            ),
          ),
          _tile(
            'Сжать PDF',
            Icons.compress,
            subtitle: 'Уменьшить размер',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CompressPdfScreen(
                  onPdfSaved: widget.onDocumentImported,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Выделить текст',
            Icons.highlight,
            isPremium: true,
            subtitle: 'Подсветка важного',
            iconColor: const Color(0xFFE8A317),
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => HighlightScreen(onSaved: widget.onDocumentImported),
            )),
          ),
          _tile(
            'Порядок страниц',
            Icons.swap_vert,
            subtitle: 'Изменение порядка PDF',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReorderPdfPagesScreen(
                  onPdfSaved: widget.onDocumentImported,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _singleRow(
          _tile(
            'Местоположение и время',
            Icons.punch_clock_rounded,
            subtitle: 'Печать геолокации/времени на фото',
            onTap: () => _addTimestamp(context),
          ),
        ),
      ],
    );
  }

  Widget _buildShareTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          'Конвертировать в PDF',
          Icons.picture_as_pdf,
          subtitle: 'Изображения → один PDF-документ',
          iconColor: Colors.red.shade700,
          onTap: () => _convertToPdf(context),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'PDF → JPEG',
            Icons.image,
            subtitle: 'Страницы PDF в изображения',
            iconColor: Colors.green.shade700,
            onTap: () => _convertToJpeg(context),
          ),
          _tile(
            'Печать',
            Icons.print,
            subtitle: 'Распечатать документ',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const PrintScreen(),
            )),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Добавить пароль',
            Icons.lock,
            subtitle: 'Защита PDF',
            isPremium: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => AddPasswordScreen(onSaved: widget.onDocumentImported),
            )),
          ),
          _tile(
            'Удалить водяной знак',
            Icons.auto_fix_normal,
            isPremium: true,
            subtitle: 'Стереть лого/знак',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => RemoveWatermarkScreen(onSaved: widget.onDocumentImported),
            )),
          ),
        ),
        const SizedBox(height: 12),
        _singleRow(
          _tile(
            'Электронная почта',
            Icons.mail_outline,
            subtitle: 'Отправить файл по почте',
            onTap: () => _shareByEmail(context),
          ),
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          'Импорт документов',
          Icons.file_download,
          subtitle: 'PDF, Word, TXT и другие форматы',
          iconColor: const Color(0xFFE67E22),
          onTap: () => _showImportOptions(context),
        ),
        const SizedBox(height: 12),
        _singleRow(
          _tile(
            'Импорт изображений',
            Icons.image_outlined,
            subtitle: 'Фото из галереи',
            iconColor: Colors.blueAccent,
            onTap: () => _importImage(context),
          ),
        ),
      ],
    );
  }

  Widget _buildAiTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          'Извлечь суть и действия',
          Icons.mobile_friendly,
          subtitle: 'AI выделяет ключевые моменты договора',
          iconColor: Colors.red.shade700,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => DocumentAiScreen.analyze(),
          )),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'AI-сканер документа',
            Icons.camera_alt,
            subtitle: 'Снимок → мгновенный анализ',
            iconColor: Colors.green.shade700,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => DocumentAiScreen.camera(),
            )),
          ),
          _tile(
            'Голосовая заметка',
            Icons.voice_chat,
            subtitle: 'Аудио-комментарий',
            isPremium: true,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VoiceNoteScreen(onSaved: widget.onDocumentImported),
            )),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'Горячая зона',
            Icons.hot_tub,
            subtitle: 'Визитка из подписи',
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => const HotZoneScreen(),
            )),
          ),
          _tile(
            'Эко упаковка',
            Icons.eco,
            subtitle: 'Анализ материалов',
            isPremium: true,
            iconColor: Colors.green.shade500,
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => DocumentAiScreen.eco(),
            )),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Действия (без изменений)
  // ------------------------------------------------------------------

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

      widget.onDocumentImported?.call();
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
    widget.onDocumentImported?.call();
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
    widget.onDocumentImported?.call();
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
      widget.onDocumentImported?.call();

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
      widget.onDocumentImported?.call();

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

      widget.onDocumentImported?.call();
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
