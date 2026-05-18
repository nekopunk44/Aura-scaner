import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;

const _documentKey = 'saved_document_paths';
const _scaleFactor = 2.0; // ~144 dpi

class MergeDocumentsScreen extends StatefulWidget {
  final VoidCallback? onMergeComplete;

  const MergeDocumentsScreen({super.key, this.onMergeComplete});

  @override
  State<MergeDocumentsScreen> createState() => _MergeDocumentsScreenState();
}

class _MergeDocumentsScreenState extends State<MergeDocumentsScreen> {
  final List<String> _selectedPaths = [];
  bool _isMerging = false;
  String _progressText = '';

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
    setState(() {
      _isMerging = true;
      _progressText = 'Подготовка...';
    });

    try {
      final outputPath = await _buildMergedPdf();

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
            content: Text('Объединено: ${p.basename(outputPath)}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isMerging = false);
    }
  }

  Future<String> _buildMergedPdf() async {
    final doc = pw.Document();

    for (int i = 0; i < _selectedPaths.length; i++) {
      final path = _selectedPaths[i];
      if (mounted) {
        setState(() =>
            _progressText = 'Обработка ${i + 1}/${_selectedPaths.length}: ${p.basename(path)}');
      }

      final ext = p.extension(path).toLowerCase().replaceAll('.', '');
      if (ext == 'jpg' || ext == 'jpeg' || ext == 'png') {
        await _addImagePage(doc, path);
      } else if (ext == 'pdf') {
        await _addPdfPages(doc, path);
      }
    }

    if (mounted) setState(() => _progressText = 'Сохранение...');

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

  Future<void> _addPdfPages(pw.Document doc, String path) async {
    final pdfDoc = await PdfDocument.openFile(path);
    try {
      for (final page in pdfDoc.pages) {
        final pdfImage = await page.render(
          fullWidth: page.width * _scaleFactor,
          fullHeight: page.height * _scaleFactor,
        );
        if (pdfImage == null) continue;
        try {
          final jpegBytes = _bgraToJpeg(pdfImage.pixels, pdfImage.width, pdfImage.height);
          final pwImage = pw.MemoryImage(jpegBytes);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat(
              page.width * _scaleFactor,
              page.height * _scaleFactor,
            ),
            margin: pw.EdgeInsets.zero,
            build: (ctx) => pw.Image(pwImage, fit: pw.BoxFit.fill),
          ));
        } finally {
          pdfImage.dispose();
        }
      }
    } finally {
      await pdfDoc.dispose();
    }
  }

  Uint8List _bgraToJpeg(Uint8List bgraPixels, int width, int height) {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bgraPixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  }

  IconData _iconForExt(String ext) =>
      ext == '.pdf' ? Icons.picture_as_pdf : Icons.image;

  Color _colorForExt(String ext) =>
      ext == '.pdf' ? Colors.red : Colors.green;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Объединить файлы'),
        actions: [
          if (_selectedPaths.length >= 2 && !_isMerging)
            TextButton.icon(
              icon: const Icon(Icons.merge_type),
              label: const Text('Объединить'),
              onPressed: _merge,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isMerging) ...[
            const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_progressText,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          ] else
            const SizedBox(height: 4),

          Expanded(
            child: _selectedPaths.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.merge_type, size: 72, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Добавьте файлы для объединения\n(PDF и изображения)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
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
                          leading: Icon(_iconForExt(ext), color: _colorForExt(ext)),
                          title: Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${index + 1}. Перетащите для изменения порядка',
                              style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: _isMerging
                                ? null
                                : () => setState(() => _selectedPaths.removeAt(index)),
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
                  label: const Text('Добавить файлы (PDF / фото)'),
                  onPressed: _isMerging ? null : _addFiles,
                  style: OutlinedButton.styleFrom(
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
                      'Объединить ${_selectedPaths.length} файла в PDF',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onPressed: _isMerging ? null : _merge,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
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
