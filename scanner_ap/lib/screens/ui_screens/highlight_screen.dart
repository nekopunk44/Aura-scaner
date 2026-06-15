import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

const _documentKey = 'saved_document_paths';

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
        if (result?.files.first.path == null) return;
        file = File(result!.files.first.path!);
      } else {
        final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (picked == null) return;
        file = File(picked.path);
      }

      File imageFile;
      if (isPdf) {
        imageFile = await _renderFirstPdfPage(file);
      } else {
        imageFile = file;
      }

      if (!mounted) return;
      final imageBytes = await imageFile.readAsBytes();
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final result = await navigator.push(
        MaterialPageRoute(
          builder: (_) => ImageEditor(image: imageBytes),
        ),
      );

      if (result != null && result is Uint8List && mounted) {
        final dir = await getApplicationDocumentsDirectory();
        final tmpPath = '${dir.path}/hl_edited_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(tmpPath).writeAsBytes(result);
        await _saveFile(File(tmpPath));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<File> _renderFirstPdfPage(File pdfFile) async {
    final pdfDoc = await PdfDocument.openFile(pdfFile.path);
    final page = pdfDoc.pages[0];
    final pdfImage = await page.render(
      fullWidth: page.width * 2,
      fullHeight: page.height * 2,
    );
    final image = img.Image.fromBytes(
      width: pdfImage!.width,
      height: pdfImage.height,
      bytes: pdfImage.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    pdfImage.dispose();
    await pdfDoc.dispose();

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/highlight_tmp.png';
    await File(path).writeAsBytes(Uint8List.fromList(img.encodePng(image)));
    return File(path);
  }

  Future<void> _saveFile(File file) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = 'highlight_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = '${dir.path}/$name';
    await file.copy(dest);

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_documentKey) ?? [];
    if (!paths.contains(dest)) {
      paths.add(dest);
      await prefs.setStringList(_documentKey, paths);
    }
    widget.onSaved?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).savedPlain), backgroundColor: Colors.green),
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
                        fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
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
