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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    try {
      setState(() => _isProcessing = true);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: dialogBg,
          content: Row(
            children: [
              const CircularProgressIndicator(color: Color(0xFF2CA5E0)),
              const SizedBox(width: 16),
              Text('Извлечение страниц...', style: TextStyle(color: textColor)),
            ],
          ),
        ),
      );

      final selectedPageNumbers = <int>[];
      for (int i = 0; i < _selectedPages.length; i++) {
        if (_selectedPages[i]) selectedPageNumbers.add(i + 1);
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text('Извлечь страницы', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _pdfInfo == null
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : Column(
              children: [
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pdfInfo!.fileName,
                              style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_pdfInfo!.pageCount} страниц · ${_pdfInfo!.fileSizeMB} MB',
                              style: TextStyle(fontSize: 12, color: subColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selectedPages.where((p) => p).length}/${_pdfInfo!.pageCount}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2CA5E0),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Введите номера страниц',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: textColor),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: _parseRangeInput,
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Например: 1,3,5 или 1-5',
                          hintStyle: TextStyle(color: subColor),
                          filled: true,
                          fillColor: cardBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: dividerColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: dividerColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFF2CA5E0)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Форматы: 1,3,5 (отдельные) · 1-5 (диапазон) · комбинация',
                        style: TextStyle(fontSize: 11, color: subColor),
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
                          icon: const Icon(Icons.check_box, size: 16),
                          label: const Text('Все'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2CA5E0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _deselectAll,
                          icon: const Icon(Icons.check_box_outline_blank, size: 16),
                          label: const Text('Очистить'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: subColor,
                            side: BorderSide(color: dividerColor),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _pdfInfo!.pageCount,
                    itemBuilder: (ctx, idx) {
                      return CheckboxListTile(
                        title: Text(
                          'Страница ${idx + 1}',
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                        value: _selectedPages[idx],
                        onChanged: (val) => setState(() => _selectedPages[idx] = val ?? false),
                        activeColor: const Color(0xFF2CA5E0),
                        checkColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        dense: true,
                      );
                    },
                  ),
                ),
                Container(
                  color: cardBg,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _pickPdf,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Другой файл'),
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
                          onPressed: _isProcessing ? null : _extractPages,
                          icon: const Icon(Icons.content_cut, size: 18),
                          label: const Text('Извлечь'),
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
                ),
              ],
            ),
    );
  }
}
