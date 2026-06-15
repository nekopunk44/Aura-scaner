import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import '../../../l10n/app_localizations.dart';

const _documentKey = 'saved_document_paths';
const _scaleFactor = 2.0; // ~144 dpi

class _BgraPayload {
  final Uint8List pixels;
  final int width;
  final int height;
  const _BgraPayload(this.pixels, this.width, this.height);
}

Uint8List _bgraToJpegIsolate(_BgraPayload payload) {
  final image = img.Image.fromBytes(
    width: payload.width,
    height: payload.height,
    bytes: payload.pixels.buffer,
    order: img.ChannelOrder.bgra,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

class MergeDocumentsScreen extends StatefulWidget {
  final VoidCallback? onMergeComplete;

  const MergeDocumentsScreen({super.key, this.onMergeComplete});

  @override
  State<MergeDocumentsScreen> createState() => _MergeDocumentsScreenState();
}

class _MergeDocumentsScreenState extends State<MergeDocumentsScreen> {
  final List<String> _selectedPaths = [];
  final Map<String, Future<Uint8List?>> _pdfThumbCache = {};
  bool _isMerging = false;
  String _progressText = '';
  double? _progressValue;

  Future<Uint8List?> _pdfThumb(String path) {
    return _pdfThumbCache.putIfAbsent(path, () async {
      try {
        final doc = await PdfDocument.openFile(path);
        try {
          final page = doc.pages.first;
          final img = await page.render(fullWidth: 160, fullHeight: 160 * page.height / page.width);
          if (img == null) return null;
          try {
            return await compute(
              _bgraToJpegIsolate,
              _BgraPayload(img.pixels, img.width, img.height),
            );
          } finally {
            img.dispose();
          }
        } finally {
          await doc.dispose();
        }
      } catch (e) {
        return null;
      }
    });
  }

  Widget _buildLeading(String path, String ext) {
    const w = 44.0;
    const h = 44.0;
    if (ext == '.jpg' || ext == '.jpeg' || ext == '.png') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          width: w,
          height: h,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(_iconForExt(ext), color: _colorForExt(ext)),
        ),
      );
    }
    if (ext == '.pdf') {
      return FutureBuilder<Uint8List?>(
        future: _pdfThumb(path),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return SizedBox(
              width: w,
              height: h,
              child: const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final bytes = snap.data;
          if (bytes == null) {
            return Icon(_iconForExt(ext), color: _colorForExt(ext));
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: w, height: h, fit: BoxFit.cover),
          );
        },
      );
    }
    return Icon(_iconForExt(ext), color: _colorForExt(ext));
  }

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null) return;
    setState(() {
      for (final file in result.files) {
        if (file.path != null && !_selectedPaths.contains(file.path)) {
          _selectedPaths.add(file.path!);
        }
      }
    });
  }

  Future<void> _merge() async {
    if (_selectedPaths.length < 2) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isMerging = true;
      _progressText = l10n.mergePreparing;
      _progressValue = null;
    });

    try {
      final outputPath = await _buildMergedPdf(l10n);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(outputPath)) {
        paths.add(outputPath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onMergeComplete?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.mergeDone(p.basename(outputPath))),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.commonError}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMerging = false;
          _progressValue = null;
        });
      }
    }
  }

  Future<String> _buildMergedPdf(AppLocalizations l10n) async {
    final doc = pw.Document();

    final totalPages = await _countTotalPages();
    int processedPages = 0;

    void bumpProgress(String label) {
      if (!mounted) return;
      setState(() {
        _progressText = label;
        _progressValue = totalPages == 0 ? null : processedPages / totalPages;
      });
    }

    for (int i = 0; i < _selectedPaths.length; i++) {
      final path = _selectedPaths[i];
      bumpProgress(l10n.mergeProcessing(i + 1, _selectedPaths.length, p.basename(path)));

      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') {
        await _addImagePage(doc, path);
        processedPages++;
        bumpProgress(l10n.mergeProcessing(i + 1, _selectedPaths.length, p.basename(path)));
      } else if (ext == 'pdf') {
        await _addPdfPages(doc, path, onPage: (pageIndex, pageTotal) {
          processedPages++;
          bumpProgress(l10n.mergeProcessingPage(
              i + 1, _selectedPaths.length, p.basename(path), pageIndex, pageTotal));
        });
      }
    }

    if (mounted) {
      setState(() {
        _progressText = l10n.mergeSaving;
        _progressValue = null;
      });
    }

    final dir = await getApplicationDocumentsDirectory();
    final outputName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final outputPath = '${dir.path}/$outputName';
    await File(outputPath).writeAsBytes(await doc.save());
    return outputPath;
  }

  Future<void> _addImagePage(pw.Document doc, String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    final pageWidth = decoded?.width.toDouble() ?? 595.0;
    final pageHeight = decoded?.height.toDouble() ?? 842.0;
    final pwImage = pw.MemoryImage(bytes);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight),
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Image(pwImage, fit: pw.BoxFit.fill),
    ));
  }

  Future<void> _addPdfPages(
    pw.Document doc,
    String path, {
    void Function(int pageIndex, int pageTotal)? onPage,
  }) async {
    final pdfDoc = await PdfDocument.openFile(path);
    try {
      final pageTotal = pdfDoc.pages.length;
      for (int i = 0; i < pageTotal; i++) {
        final page = pdfDoc.pages[i];
        final pdfImage = await page.render(
          fullWidth: page.width * _scaleFactor,
          fullHeight: page.height * _scaleFactor,
        );
        if (pdfImage == null) continue;
        try {
          final jpegBytes = await compute(
            _bgraToJpegIsolate,
            _BgraPayload(pdfImage.pixels, pdfImage.width, pdfImage.height),
          );
          final pwImage = pw.MemoryImage(jpegBytes);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat(
              page.width * _scaleFactor,
              page.height * _scaleFactor,
            ),
            margin: pw.EdgeInsets.zero,
            build: (ctx) => pw.Image(pwImage, fit: pw.BoxFit.fill),
          ));
          onPage?.call(i + 1, pageTotal);
        } finally {
          pdfImage.dispose();
        }
      }
    } finally {
      await pdfDoc.dispose();
    }
  }

  Future<int> _countTotalPages() async {
    int total = 0;
    for (final path in _selectedPaths) {
      final ext = p.extension(path).toLowerCase();
      if (ext == '.pdf') {
        try {
          final doc = await PdfDocument.openFile(path);
          total += doc.pages.length;
          await doc.dispose();
        } catch (_) {
          total += 1;
        }
      } else {
        total += 1;
      }
    }
    return total;
  }

  IconData _iconForExt(String ext) =>
      ext == '.pdf' ? Icons.picture_as_pdf : Icons.image;

  Color _colorForExt(String ext) =>
      ext == '.pdf' ? Colors.red : Colors.green;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.featMerge),
        actions: [
          if (_selectedPaths.length >= 2 && !_isMerging)
            TextButton.icon(
              icon: const Icon(Icons.merge_type),
              label: Text(l10n.mergeAction),
              onPressed: _merge,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isMerging) ...[
            LinearProgressIndicator(
              value: _progressValue,
              color: const Color(0xFF2CA5E0),
              backgroundColor: const Color(0xFF2CA5E0).withValues(alpha: 0.15),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_progressText,
                  style: TextStyle(color: subColor, fontSize: 13)),
            ),
          ] else
            const SizedBox(height: 4),

          Expanded(
            child: _selectedPaths.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.merge_type, size: 72, color: subColor),
                        const SizedBox(height: 16),
                        Text(
                          l10n.mergeEmptyHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _selectedPaths.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _selectedPaths.removeAt(oldIndex);
                        _selectedPaths.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final path = _selectedPaths[index];
                      final name = p.basename(path);
                      final ext = p.extension(path).toLowerCase();
                      return Card(
                        key: ValueKey(path),
                        child: ListTile(
                          leading: _buildLeading(path, ext),
                          title: Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(l10n.mergeItemSubtitle(index + 1),
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: Icon(Icons.close, color: subColor),
                            onPressed: _isMerging
                                ? null
                                : () => setState(() {
                                      final removed = _selectedPaths.removeAt(index);
                                      _pdfThumbCache.remove(removed);
                                    }),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.mergeAddFiles),
                  onPressed: _isMerging ? null : _addFiles,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2CA5E0),
                    side: const BorderSide(color: Color(0xFF2CA5E0)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (_selectedPaths.length >= 2) ...[
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.merge_type, color: Colors.white),
                    label: Text(
                      l10n.mergeCountToPdf(_selectedPaths.length),
                      style: const TextStyle(color: Colors.white),
                    ),
                    onPressed: _isMerging ? null : _merge,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2CA5E0),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
