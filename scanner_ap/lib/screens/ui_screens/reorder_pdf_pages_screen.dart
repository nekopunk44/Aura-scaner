import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;

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
        SnackBar(content: Text('Ошибка загрузки PDF: $e')),
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
            content: Text('PDF сохранён: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Реупорядочивание страниц PDF'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              _isDeleteMode = !_isDeleteMode;
              setState(() {});
            },
            icon: Icon(_isDeleteMode ? Icons.layers : Icons.delete),
            label: Text(_isDeleteMode ? 'Порядок' : 'Удалить'),
          ),
        ],
      ),
      body: _pdfDoc == null || _pageOrder.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
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
                            ? () {
                                setState(() {
                                  _selectedPages[_pageOrder[idx]] =
                                      !_selectedPages[_pageOrder[idx]];
                                });
                              }
                            : null,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? Colors.red : Colors.grey,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: isSelected
                                ? Colors.red.withValues(alpha: 0.1)
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              if (!_isDeleteMode)
                                ReorderableDragStartListener(
                                  index: idx,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Text(
                                    'Страница $pageNum',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              if (_isDeleteMode && isSelected)
                                const Icon(Icons.check_circle, color: Colors.red),
                            ],
                          ),
                        ),
                      );
                    },
                    itemCount: _pageOrder.length,
                  ),
                ),

                // Кнопки
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_isDeleteMode)
                        ElevatedButton.icon(
                          onPressed:
                              _selectedPages.contains(true) ? _deleteSelectedPages : null,
                          icon: const Icon(Icons.delete),
                          label: const Text('Удалить выбранные'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        )
                      else
                        const Text(
                          'Перетаскивайте страницы для переупорядочивания',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : () => _pickPdf(),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Выбрать другой PDF'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _savePdf,
                              icon: const Icon(Icons.check),
                              label: const Text('Сохранить'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
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
