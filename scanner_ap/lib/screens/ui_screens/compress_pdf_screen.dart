import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/pdf_service.dart';
import '../../l10n/app_localizations.dart';

const String _documentKey = 'saved_document_paths';

class CompressPdfScreen extends StatefulWidget {
  final VoidCallback? onPdfSaved;

  const CompressPdfScreen({super.key, this.onPdfSaved});

  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  String? _selectedPdfPath;
  double _qualityFactor = 0.7;
  bool _isProcessing = false;
  PdfInfo? _pdfInfo;
  final ValueNotifier<({int current, int total})> _compressProgress =
      ValueNotifier((current: 0, total: 0));

  @override
  void dispose() {
    _compressProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _pickPdf();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result == null || result.files.first.path == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    _selectedPdfPath = result.files.first.path;

    try {
      _pdfInfo = await PdfService.getPdfInfo(_selectedPdfPath!);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context).commonError}: $e')),
      );
    }
  }

  Future<void> _compressAndSave() async {
    if (_selectedPdfPath == null) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    try {
      setState(() => _isProcessing = true);
      _compressProgress.value = (current: 0, total: _pdfInfo?.pageCount ?? 0);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: dialogBg,
          content: ValueListenableBuilder<({int current, int total})>(
            valueListenable: _compressProgress,
            builder: (ctx, p, _) {
              final ratio = p.total == 0 ? null : p.current / p.total;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.total == 0
                        ? l10n.compressInProgress
                        : l10n.compressProgress(p.current, p.total),
                    style: TextStyle(color: textColor),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: ratio,
                    color: const Color(0xFF2CA5E0),
                    backgroundColor: const Color(0xFF2CA5E0).withValues(alpha: 0.15),
                  ),
                ],
              );
            },
          ),
        ),
      );

      final compressedBytes = await PdfService.compressPdf(
        pdfPath: _selectedPdfPath!,
        qualityFactor: _qualityFactor,
        onProgress: (current, total) {
          if (!mounted) return;
          _compressProgress.value = (current: current, total: total);
        },
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = '${dir.path}/$fileName';

      await File(outputPath).writeAsBytes(compressedBytes);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(outputPath)) {
        paths.add(outputPath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onPdfSaved?.call();

      if (!mounted) return;
      navigator.pop();

      final originalSize = _pdfInfo?.fileSizeBytes ?? 0;
      final compressedSize = compressedBytes.length;
      final reduction = originalSize > 0
          ? ((1 - compressedSize / originalSize) * 100).toStringAsFixed(1)
          : '0.0';

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.compressResult(
              reduction,
              (originalSize / 1024).toStringAsFixed(2),
              (compressedSize / 1024).toStringAsFixed(2),
            ),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.commonError}: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8EDF5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.featCompressPdf, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _pdfInfo == null
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.fileInfo,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textColor),
                        ),
                        const SizedBox(height: 12),
                        _InfoRow(label: l10n.fileInfoName, value: _pdfInfo!.fileName, textColor: textColor, subColor: subColor),
                        const SizedBox(height: 6),
                        _InfoRow(label: l10n.fileInfoSize, value: '${_pdfInfo!.fileSizeMB} MB', textColor: textColor, subColor: subColor),
                        const SizedBox(height: 6),
                        _InfoRow(label: l10n.fileInfoPages, value: '${_pdfInfo!.pageCount}', textColor: textColor, subColor: subColor),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.compressLevel,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textColor),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: dividerColor),
                    ),
                    child: RadioGroup<double>(
                      groupValue: _qualityFactor,
                      onChanged: (v) => setState(() => _qualityFactor = v!),
                      child: Column(
                        children: [
                          _QualityOption(title: l10n.compressQMaxTitle, subtitle: l10n.compressQMaxSub, value: 0.9, textColor: textColor, subColor: subColor),
                          Divider(height: 1, color: dividerColor),
                          _QualityOption(title: l10n.compressQGoodTitle, subtitle: l10n.compressQGoodSub, value: 0.7, textColor: textColor, subColor: subColor),
                          Divider(height: 1, color: dividerColor),
                          _QualityOption(title: l10n.compressQMedTitle, subtitle: l10n.compressQMedSub, value: 0.5, textColor: textColor, subColor: subColor),
                          Divider(height: 1, color: dividerColor),
                          _QualityOption(title: l10n.compressQLowTitle, subtitle: l10n.compressQLowSub, value: 0.3, textColor: textColor, subColor: subColor),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2CA5E0).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2CA5E0).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: const Color(0xFF2CA5E0)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.compressNote,
                            style: TextStyle(fontSize: 12, color: const Color(0xFF2CA5E0), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _pickPdf,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: Text(l10n.otherFile),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2CA5E0),
                            side: const BorderSide(color: Color(0xFF2CA5E0)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _compressAndSave,
                          icon: const Icon(Icons.compress, size: 18),
                          label: Text(l10n.compressAction),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            disabledBackgroundColor: Colors.green.shade600.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color textColor;
  final Color subColor;

  const _InfoRow({required this.label, required this.value, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: subColor)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _QualityOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final Color textColor;
  final Color subColor;

  const _QualityOption({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<double>(
      title: Text(title, style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: subColor)),
      value: value,
      activeColor: const Color(0xFF2CA5E0),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}
