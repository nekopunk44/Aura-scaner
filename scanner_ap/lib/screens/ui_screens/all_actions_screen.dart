import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'camera.dart';
import 'ui_helpers.dart';
import 'package:path/path.dart' as p;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/document_registry.dart';
import '../../services/premium_service.dart';
import 'premium_paywall.dart';
import 'add_password_screen.dart';
import 'restore_photo_screen.dart';
import 'highlight_screen.dart';
import 'document_ai_screen.dart';
import 'eco/eco_packaging_screen.dart';
import 'geo_stamp_editor_screen.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import 'ocr/ocr_screen.dart';
import 'pdf_tools_screen.dart';
import 'photo_editor_screen.dart';
import 'signature/home_screen.dart' as sig;
import 'remove_spots_screen.dart';
import 'voice_note_screen.dart';
import 'print_screen.dart';
import 'remove_watermark_screen.dart';
import 'hot_zone_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_notification.dart';

const _documentKey = 'saved_document_paths';

class AllActionsScreen extends StatefulWidget {
  final VoidCallback? onDocumentImported;

  const AllActionsScreen({super.key, this.onDocumentImported});

  @override
  State<AllActionsScreen> createState() => _AllActionsScreenState();
}

class _AllActionsScreenState extends State<AllActionsScreen>
    with TickerProviderStateMixin {
  static const _categoryIcons = [
    Icons.camera_alt_outlined,
    Icons.tune,
    Icons.ios_share_outlined,
  ];

  List<String> _categoryLabels(AppLocalizations l10n) => [
    l10n.tabScan,
    l10n.tabEdit,
    l10n.tabShare,
  ];

  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _categoryIcons.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
        ? () => showPremiumPaywall(context, title)
        : onTap ??
              () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).featInDevelopment(title),
                  ),
                ),
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
        ? () => showPremiumPaywall(context, title)
        : onTap ??
              () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context).featInDevelopment(title),
                  ),
                ),
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
        ? () => showPremiumPaywall(context, title)
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
                              horizontal: 7,
                              vertical: 3,
                            ),
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
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pairRow(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _singleRow(Widget child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                    l10n.aiTitleAnalyze,
                    l10n.featAiAnalyzeSub,
                    Icons.auto_awesome,
                    gradient: const [
                      Color(0xFF6FCFF5),
                      Color(0xFF2CA5E0),
                      Color(0xFF1565C0),
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DocumentAiScreen.camera(),
                      ),
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
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: Colors.transparent,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                padding: const EdgeInsets.all(4),
                tabs: [
                  for (var i = 0; i < _categoryIcons.length; i++)
                    Tab(
                      height: 44,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_categoryIcons[i], size: 16),
                            const SizedBox(width: 6),
                            Text(
                              _categoryLabels(AppLocalizations.of(context))[i],
                            ),
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
              children: [_buildScanTab(), _buildEditTab(), _buildShareTab()],
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
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          l10n.featDocument,
          Icons.description,
          iconColor: Colors.purple,
          subtitle: l10n.featDocumentSub,
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
            l10n.featIdCard,
            Icons.add_card,
            subtitle: l10n.featIdCardSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CameraScreen(initialFeature: 'Удостоверение личности'),
              ),
            ),
          ),
          _tile(
            l10n.featPassport,
            Icons.man,
            subtitle: l10n.featPassportSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CameraScreen(initialFeature: 'Паспорт'),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.feat10PagesTitle,
            Icons.library_books,
            isPremium: true,
            subtitle: l10n.feat10PagesSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CameraScreen(initialFeature: '+10 страниц'),
              ),
            ),
          ),
          _tile(
            l10n.featTranslate,
            Icons.translate,
            subtitle: l10n.featTranslateSub,
            iconColor: const Color(0xFFE67E22),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraScreen(initialFeature: 'Перевод'),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featQr,
            Icons.qr_code_2,
            subtitle: l10n.featQrSub,
            iconColor: Colors.teal,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CameraScreen(initialFeature: 'Сканер qr-код'),
                ),
              );
            },
          ),
          _tile(
            l10n.featVoiceNote,
            Icons.voice_chat,
            subtitle: l10n.featVoiceNoteSub,
            isPremium: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    VoiceNoteScreen(onSaved: widget.onDocumentImported),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featHotZone,
            Icons.hot_tub,
            subtitle: l10n.featHotZoneSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HotZoneScreen()),
            ),
          ),
          _tile(
            l10n.featEcoPackage,
            Icons.eco,
            subtitle: l10n.featEcoPackageSub,
            isPremium: true,
            iconColor: Colors.green.shade500,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EcoPackagingScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          l10n.featColorCrop,
          Icons.tune,
          iconColor: Colors.red,
          subtitle: l10n.featColorCropSub,
          onTap: () => _editPhoto(
            context,
            tools: const [
              PhotoEditorTool.crop,
              PhotoEditorTool.brightness,
              PhotoEditorTool.contrast,
              PhotoEditorTool.bw,
            ],
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featSignature,
            Icons.edit_note,
            iconColor: Colors.green,
            subtitle: l10n.featSignatureSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const sig.HomeScreen()),
            ),
          ),
          _tile(
            l10n.featRestorePhoto,
            Icons.auto_fix_high,
            isPremium: true,
            subtitle: l10n.featRestorePhotoSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RestorePhotoScreen(onSaved: widget.onDocumentImported),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featRemoveSpots,
            Icons.layers_clear,
            subtitle: l10n.featRemoveSpotsSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RemoveSpotsScreen(onImageSaved: widget.onDocumentImported),
              ),
            ),
          ),
          _tile(
            'OCR',
            Icons.text_fields_outlined,
            iconColor: const Color(0xFF6B7A99),
            subtitle: l10n.featOcrSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OcrScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featHighlight,
            Icons.highlight,
            isPremium: true,
            subtitle: l10n.featHighlightSub,
            iconColor: const Color(0xFFE8A317),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    HighlightScreen(onSaved: widget.onDocumentImported),
              ),
            ),
          ),
          _tile(
            l10n.featPdfTools,
            Icons.picture_as_pdf,
            iconColor: Colors.red,
            subtitle: l10n.featPdfToolsSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PdfToolsScreen(onSaved: widget.onDocumentImported),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _singleRow(
          _tile(
            l10n.featGeoStamp,
            Icons.punch_clock_rounded,
            subtitle: l10n.featGeoStampSub,
            onTap: () => _addTimestamp(context),
          ),
        ),
      ],
    );
  }

  Widget _buildShareTab() {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        _wideTile(
          l10n.featAddPassword,
          Icons.lock,
          subtitle: l10n.featAddPasswordSub,
          iconColor: const Color(0xFFE8A317),
          isPremium: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddPasswordScreen(onSaved: widget.onDocumentImported),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            'PDF/JPEG',
            Icons.swap_horiz_rounded,
            subtitle: l10n.featPdfToImagesSub,
            iconColor: const Color(0xFF2CA5E0),
            onTap: () => _convertPdfJpeg(context),
          ),
          _tile(
            l10n.featPrint,
            Icons.print,
            subtitle: l10n.featPrintSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintScreen()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _pairRow(
          _tile(
            l10n.featRemoveWatermark,
            Icons.auto_fix_normal,
            isPremium: true,
            subtitle: l10n.featRemoveWatermarkSub,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RemoveWatermarkScreen(onSaved: widget.onDocumentImported),
              ),
            ),
          ),
          _tile(
            l10n.featEmail,
            Icons.mail_outline,
            subtitle: l10n.featEmailSub,
            onTap: () => _shareByEmail(context),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Действия (без изменений)
  // ------------------------------------------------------------------

  Future<void> _editPhoto(
    BuildContext context, {
    List<PhotoEditorTool>? tools,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditorScreen(
          imagePath: picked.path,
          onSaved: widget.onDocumentImported,
          tools: tools ?? PhotoEditorTool.values,
        ),
      ),
    );
  }

  Future<void> _addTimestamp(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    // Открываем интерактивный редактор метки (перетаскивание, размер, стиль,
    // цвет, геолокация). Сохранение/регистрация документа — внутри редактора.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GeoStampEditorScreen(
          imagePath: picked.path,
          onSaved: widget.onDocumentImported,
        ),
      ),
    );
  }

  Future<void> _convertPdfJpeg(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final selectedPaths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
    if (selectedPaths.isEmpty) return;

    final pdfPaths = selectedPaths
        .where((path) => p.extension(path).toLowerCase() == '.pdf')
        .toList(growable: false);
    final imagePaths = selectedPaths
        .where((path) {
          final ext = p.extension(path).toLowerCase();
          return ext == '.jpg' || ext == '.jpeg' || ext == '.png';
        })
        .toList(growable: false);

    if (!context.mounted) return;

    if (pdfPaths.isNotEmpty && imagePaths.isNotEmpty) {
      _showNotice(context, '${l10n.commonError}: PDF / JPEG');
      return;
    }
    if (pdfPaths.length == 1) {
      await _convertToJpeg(context, pdfPaths.first);
      return;
    }
    if (pdfPaths.length > 1 || imagePaths.isEmpty) {
      _showNotice(context, l10n.commonError);
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.converting),
            ],
          ),
        ),
      );
    }

    try {
      final doc = pw.Document();
      for (final path in imagePaths) {
        final bytes = await File(path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(
              decoded?.width.toDouble() ?? 595,
              decoded?.height.toDouble() ?? 842,
            ),
            margin: pw.EdgeInsets.zero,
            build: (ctx) =>
                pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.fill),
          ),
        );
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
      await DocumentRegistry().add(
        DocEntry(
          localPath: outputPath,
          remoteId: null,
          name: p.basenameWithoutExtension(fileName),
        ),
      );
      widget.onDocumentImported?.call();

      if (context.mounted) {
        Navigator.pop(context);
        _showNotice(
          context,
          l10n.snackPdfCreated(fileName),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showNotice(context, '${l10n.commonError}: $e');
      }
    }
  }

  Future<void> _convertToJpeg(BuildContext context, String pdfPath) async {
    final l10n = AppLocalizations.of(context);
    final baseName = p.basenameWithoutExtension(pdfPath);

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Text(l10n.converting),
            ],
          ),
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
            final jpegBytes = Uint8List.fromList(
              img.encodeJpg(imgImage, quality: 90),
            );
            final fileName = '${baseName}_page${i + 1}.jpg';
            final outputPath = '${dir.path}/$fileName';
            await File(outputPath).writeAsBytes(jpegBytes);
            if (!paths.contains(outputPath)) paths.add(outputPath);
            // Регистрируем в DocumentRegistry — иначе вкладка «Файлы»
            // этих JPEG не увидит (MyDocumentsScreen читает registry,
            // а не legacy _documentKey).
            await DocumentRegistry().add(
              DocEntry(
                localPath: outputPath,
                remoteId: null,
                name: '${baseName}_page${i + 1}',
              ),
            );
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

      if (context.mounted) {
        Navigator.pop(context);
        _showNotice(
          context,
          l10n.snackSavedImages(saved),
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showNotice(context, '${l10n.commonError}: $e');
      }
    }
  }

  void _showNotice(
    BuildContext context,
    String message, {
    NotificationType type = NotificationType.error,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.clearSnackBars();
    AppNotification.show(context, message: message, type: type);
  }

  Future<void> _shareByEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.first.path == null) return;

    final path = result.files.first.path!;
    if (!await File(path).exists()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.docFileNotFound)));
      return;
    }
    await Share.shareXFiles([XFile(path)], subject: p.basename(path));
  }
}
