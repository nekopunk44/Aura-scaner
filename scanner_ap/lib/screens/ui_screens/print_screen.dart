import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../l10n/app_localizations.dart';

class PrintScreen extends StatefulWidget {
  const PrintScreen({super.key});

  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  bool _isPrinting = false;

  Future<void> _printPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    if (result == null || result.files.first.path == null) return;
    final bytes = await File(result.files.first.path!).readAsBytes();
    if (!mounted) return;
    setState(() => _isPrinting = true);
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _printImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final imageBytes = await File(picked.path).readAsBytes();
    if (!mounted) return;
    setState(() => _isPrinting = true);
    try {
      final image = await flutterImageProvider(MemoryImage(imageBytes));
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Image(image, fit: pw.BoxFit.contain),
        ),
      ));
      await Printing.layoutPdf(onLayout: (_) => doc.save());
    } finally {
      if (mounted) setState(() => _isPrinting = false);
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
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.printTitle,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isDark ? null : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.print, color: Color(0xFF2CA5E0), size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(l10n.printTitle,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: textColor)),
                  const SizedBox(height: 6),
                  Text(l10n.printSelectFile,
                      style: TextStyle(fontSize: 13, color: subColor)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildButton(
              icon: Icons.picture_as_pdf,
              label: l10n.printPdf,
              subLabel: l10n.pwdSelectPdfFile,
              color: Colors.red.shade600,
              onTap: _isPrinting ? null : _printPdf,
            ),
            const SizedBox(height: 14),
            _buildButton(
              icon: Icons.image_outlined,
              label: l10n.printImage,
              subLabel: l10n.printSelectImage,
              color: const Color(0xFF2CA5E0),
              onTap: _isPrinting ? null : _printImage,
            ),
            if (_isPrinting) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0))),
              const SizedBox(height: 12),
              Center(
                child: Text(l10n.printPreparing,
                    style: TextStyle(color: subColor, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required String subLabel,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(subLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
          ],
        ),
      ),
    );
  }
}
