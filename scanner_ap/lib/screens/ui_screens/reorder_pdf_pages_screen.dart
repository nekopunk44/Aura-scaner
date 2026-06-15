import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import '../../l10n/app_localizations.dart';

const String _documentKey = 'saved_document_paths';

class ReorderPdfPagesScreen extends StatefulWidget {
  final VoidCallback? onPdfSaved;

  const ReorderPdfPagesScreen({super.key, this.onPdfSaved});

  @override
  State<ReorderPdfPagesScreen> createState() => _ReorderPdfPagesScreenState();
}

class _ReorderPdfPagesScreenState extends State<ReorderPdfPagesScreen> {
  String? _pdfPath;
  PdfDocument? _pdfDoc;
  List<int> _pageOrder = [];
  List<bool> _selectedPages = [];
  bool _isProcessing = false;
  bool _isDeleteMode = false; // true = режим удаления, false = переупорядочивание

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

    _pdfPath = result.files.first.path!;

    try {
      _pdfDoc = await PdfDocument.openFile(_pdfPath!);
      final count = _pdfDoc!.pages.length;
      _pageOrder = List.generate(count, (i) => i);
      _selectedPages = List.filled(count, false);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context).reorderLoadError}: $e')),
      );
    }
  }

  void _deleteSelectedPages() {
    _pageOrder.removeWhere((pageIdx) => _selectedPages[pageIdx]);
    _selectedPages = List.filled(_pdfDoc!.pages.length, false);
    setState(() {});
  }

  Future<void> _savePdf() async {
    if (_pdfDoc == null || _pageOrder.isEmpty) return;
    final l10n = AppLocalizations.of(context);

    try {
      setState(() => _isProcessing = true);

      final doc = pw.Document();
      final pdfWidth = PdfPageFormat.a4.width;
      final pdfHeight = PdfPageFormat.a4.height;

      for (int pageIdx in _pageOrder) {
        final page = _pdfDoc!.pages[pageIdx];
        final pdfImage = await page.render(
          fullWidth: 1024,
          fullHeight: 1024,
        );

        if (pdfImage != null) {
          try {
            final imgImage = img.Image.fromBytes(
              width: pdfImage.width,
              height: pdfImage.height,
              bytes: pdfImage.pixels.buffer,
              order: img.ChannelOrder.bgra,
            );
            final pngBytes = img.encodePng(imgImage);

            doc.addPage(pw.Page(
              pageFormat: PdfPageFormat(pdfWidth, pdfHeight),
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Image(
                pw.MemoryImage(pngBytes),
                fit: pw.BoxFit.fill,
              ),
            ));
          } finally {
            pdfImage.dispose();
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'reordered_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = '${dir.path}/$fileName';

      await File(outputPath).writeAsBytes(await doc.save());

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(outputPath)) {
        paths.add(outputPath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onPdfSaved?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.reorderSaved(fileName)),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.reorderSaveError}: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  void dispose() {
    _pdfDoc?.dispose();
    super.dispose();
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
        title: Text(l10n.reorderTitle, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _isDeleteMode = !_isDeleteMode),
            icon: Icon(_isDeleteMode ? Icons.layers : Icons.delete_outline,
                color: _isDeleteMode ? const Color(0xFF2CA5E0) : Colors.red.shade400, size: 18),
            label: Text(
              _isDeleteMode ? l10n.reorderModeReorder : l10n.actionDelete,
              style: TextStyle(color: _isDeleteMode ? const Color(0xFF2CA5E0) : Colors.red.shade400),
            ),
          ),
        ],
      ),
      body: _pdfDoc == null || _pageOrder.isEmpty
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    onReorder: (oldIdx, newIdx) {
                      setState(() {
                        if (newIdx > oldIdx) newIdx -= 1;
                        final page = _pageOrder.removeAt(oldIdx);
                        _pageOrder.insert(newIdx, page);
                      });
                    },
                    itemBuilder: (ctx, idx) {
                      final pageNum = _pageOrder[idx] + 1;
                      final isSelected = _selectedPages[_pageOrder[idx]];

                      return GestureDetector(
                        key: ValueKey(pageNum),
                        onTap: _isDeleteMode
                            ? () => setState(() => _selectedPages[_pageOrder[idx]] = !_selectedPages[_pageOrder[idx]])
                            : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? Colors.red.shade400 : dividerColor,
                              width: isSelected ? 1.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: isSelected ? Colors.red.withValues(alpha: 0.08) : cardBg,
                          ),
                          child: Row(
                            children: [
                              if (!_isDeleteMode)
                                ReorderableDragStartListener(
                                  index: idx,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(Icons.drag_handle, color: subColor),
                                  ),
                                )
                              else
                                const SizedBox(width: 12),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                                  child: Text(
                                    l10n.pageLabel(pageNum),
                                    style: TextStyle(fontSize: 15, color: textColor, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                              if (_isDeleteMode)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Icon(
                                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                    color: isSelected ? Colors.red.shade400 : subColor,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                    itemCount: _pageOrder.length,
                  ),
                ),
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      if (_isDeleteMode)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _selectedPages.contains(true) ? _deleteSelectedPages : null,
                            icon: const Icon(Icons.delete, size: 18),
                            label: Text(l10n.reorderDeleteSelected),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              disabledBackgroundColor: Colors.red.shade600.withValues(alpha: 0.4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        )
                      else
                        Text(
                          l10n.reorderDragHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor, fontSize: 13),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing ? null : _pickPdf,
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: Text(l10n.reorderOtherPdf),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2CA5E0),
                                side: const BorderSide(color: Color(0xFF2CA5E0)),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _savePdf,
                              icon: const Icon(Icons.check, size: 18),
                              label: Text(l10n.actionSave),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                disabledBackgroundColor: Colors.green.shade600.withValues(alpha: 0.4),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
