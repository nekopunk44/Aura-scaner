import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../services/document_registry.dart';
import 'highlight_editor_screen.dart';

const _documentKey = 'saved_document_paths';
const _maxPages = 30; // защита от OOM на огромных PDF

class HighlightScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const HighlightScreen({super.key, this.onSaved});

  @override
  State<HighlightScreen> createState() => _HighlightScreenState();
}

class _HighlightScreenState extends State<HighlightScreen> {
  bool _isLoading = false;

  Future<void> _pickAndOpen({required bool isPdf}) async {
    setState(() => _isLoading = true);
    try {
      File? file;
      if (isPdf) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        final path = result?.files.first.path;
        if (path == null) return;
        file = File(path);
      } else {
        final picked =
            await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        file = File(picked.path);
      }

      final List<Uint8List> pages = isPdf
          ? await _renderAllPdfPages(file)
          : <Uint8List>[await file.readAsBytes()];
      if (pages.isEmpty || !mounted) return;

      final navigator = Navigator.of(context);
      final result = await navigator.push<List<Uint8List>>(
        MaterialPageRoute(
          builder: (_) => HighlightEditorScreen(pages: pages, textMode: isPdf),
        ),
      );
      if (result == null || result.isEmpty || !mounted) return;

      await _saveResult(result, asPdf: isPdf);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Рендерит все страницы PDF (до [_maxPages]) в PNG-байты.
  Future<List<Uint8List>> _renderAllPdfPages(File pdfFile) async {
    final doc = await PdfDocument.openFile(pdfFile.path);
    final out = <Uint8List>[];
    try {
      final count = doc.pages.length.clamp(0, _maxPages);
      for (var i = 0; i < count; i++) {
        final page = doc.pages[i];
        final rendered = await page.render(
          fullWidth: page.width * 2,
          fullHeight: page.height * 2,
        );
        if (rendered == null) continue;
        final image = img.Image.fromBytes(
          width: rendered.width,
          height: rendered.height,
          bytes: rendered.pixels.buffer,
          order: img.ChannelOrder.bgra,
        );
        rendered.dispose();
        out.add(Uint8List.fromList(img.encodePng(image)));
      }
    } finally {
      await doc.dispose();
    }
    return out;
  }

  /// Сохраняет результат: многостраничный документ — в PDF, одиночную
  /// картинку — в JPG. Регистрирует в списке документов.
  Future<void> _saveResult(List<Uint8List> pages, {required bool asPdf}) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final String dest;

    if (asPdf || pages.length > 1) {
      final pdfDoc = pw.Document();
      for (final bytes in pages) {
        final image = pw.MemoryImage(bytes);
        final w = (image.width ?? 1000).toDouble();
        final h = (image.height ?? 1414).toDouble();
        pdfDoc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(w, h),
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
          ),
        );
      }
      dest = '${dir.path}/highlight_$ts.pdf';
      await File(dest).writeAsBytes(await pdfDoc.save());
    } else {
      final decoded = img.decodeImage(pages.first);
      final jpg = decoded != null
          ? img.encodeJpg(decoded, quality: 92)
          : pages.first;
      dest = '${dir.path}/highlight_$ts.jpg';
      await File(dest).writeAsBytes(Uint8List.fromList(jpg));
    }

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_documentKey) ?? [];
    if (!paths.contains(dest)) {
      paths.add(dest);
      await prefs.setStringList(_documentKey, paths);
    }
    await DocumentRegistry().load();
    await DocumentRegistry().add(
      DocEntry(
        localPath: dest,
        remoteId: null,
        name: DocumentRegistry.nameFromPath(dest),
      ),
    );

    widget.onSaved?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).savedPlain),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.highlightTitle),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.highlightSelectDoc,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.highlightEditorHint,
                    style: TextStyle(fontSize: 13, color: subColor, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  _PickTile(
                    icon: Icons.picture_as_pdf,
                    iconColor: Colors.red.shade400,
                    title: l10n.importPdfDocument,
                    subtitle: l10n.highlightPdfSub,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickAndOpen(isPdf: true),
                  ),
                  const SizedBox(height: 12),
                  _PickTile(
                    icon: Icons.image_outlined,
                    iconColor: Colors.blue.shade400,
                    title: l10n.highlightImage,
                    subtitle: l10n.highlightImageSub,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickAndOpen(isPdf: false),
                  ),
                ],
              ),
            ),
    );
  }
}

class _PickTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _PickTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.cardBg,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(fontSize: 12, color: subColor)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: subColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
