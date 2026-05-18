import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/pdf_service.dart';

const String _documentKey = 'saved_document_paths';

class ExtractPdfPagesScreen extends StatefulWidget {
  final VoidCallback? onPdfSaved;

  const ExtractPdfPagesScreen({super.key, this.onPdfSaved});

  @override
  State<ExtractPdfPagesScreen> createState() => _ExtractPdfPagesScreenState();
}

class _ExtractPdfPagesScreenState extends State<ExtractPdfPagesScreen> {
  String? _selectedPdfPath;
  PdfInfo? _pdfInfo;
  List<bool> _selectedPages = [];
  bool _isProcessing = false;

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
      _selectedPages = List.filled(_pdfInfo!.pageCount, false);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  void _parseRangeInput(String input) {
    if (input.isEmpty) {
      _selectedPages = List.filled(_pdfInfo!.pageCount, false);
      setState(() {});
      return;
    }

    _selectedPages = List.filled(_pdfInfo!.pageCount, false);

    try {
      final parts = input.split(',');
      for (var part in parts) {
        part = part.trim();
        if (part.contains('-')) {
          final range = part.split('-');
          final start = int.parse(range[0].trim());
          final end = int.parse(range[1].trim());
          for (int i = start; i <= end && i <= _pdfInfo!.pageCount; i++) {
            if (i > 0) _selectedPages[i - 1] = true;
          }
        } else {
          final page = int.parse(part);
          if (page > 0 && page <= _pdfInfo!.pageCount) {
            _selectedPages[page - 1] = true;
          }
        }
      }
      setState(() {});
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный формат диапазона')),
      );
    }
  }

  void _selectAll() {
    _selectedPages = List.filled(_pdfInfo!.pageCount, true);
    setState(() {});
  }

  void _deselectAll() {
    _selectedPages = List.filled(_pdfInfo!.pageCount, false);
    setState(() {});
  }

  Future<void> _extractPages() async {
    if (_selectedPdfPath == null || !_selectedPages.contains(true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одну страницу')),
      );
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      setState(() => _isProcessing = true);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Извлечение страниц...'),
            ],
          ),
        ),
      );

      final selectedPageNumbers = <int>[];
      for (int i = 0; i < _selectedPages.length; i++) {
        if (_selectedPages[i]) {
          selectedPageNumbers.add(i + 1);
        }
      }

      final extractedBytes = await PdfService.extractPages(
        pdfPath: _selectedPdfPath!,
        pageNumbers: selectedPageNumbers,
      );

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'extracted_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final outputPath = '${dir.path}/$fileName';

      await File(outputPath).writeAsBytes(extractedBytes);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(outputPath)) {
        paths.add(outputPath);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onPdfSaved?.call();

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Извлечено ${selectedPageNumbers.length} страниц(ы)'),
          backgroundColor: Colors.green,
        ),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Извлечь страницы PDF'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _pdfInfo == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.grey[100],
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pdfInfo!.fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_pdfInfo!.pageCount} страниц, ${_pdfInfo!.fileSizeMB} MB',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Text(
                        '${_selectedPages.where((p) => p).length}/${_pdfInfo!.pageCount}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Введите номера страниц:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: _parseRangeInput,
                        decoration: InputDecoration(
                          hintText: 'Примеры: 1,3,5 или 1-5 или 1,3-5',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Форматы: 1,3,5 (отдельные) или 1-5 (диапазон) или комбинация',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _selectAll,
                          icon: const Icon(Icons.check_box),
                          label: const Text('Всё'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _deselectAll,
                          icon: const Icon(Icons.check_box_outline_blank),
                          label: const Text('Очистить'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _pdfInfo!.pageCount,
                    itemBuilder: (ctx, idx) {
                      return CheckboxListTile(
                        title: Text('Страница ${idx + 1}'),
                        value: _selectedPages[idx],
                        onChanged: (val) {
                          setState(() => _selectedPages[idx] = val ?? false);
                        },
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _pickPdf,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Выбрать другой'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _extractPages,
                          icon: const Icon(Icons.content_cut),
                          label: const Text('Извлечь'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
