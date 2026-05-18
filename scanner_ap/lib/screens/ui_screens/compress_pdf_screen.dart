import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/pdf_service.dart';

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
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  Future<void> _compressAndSave() async {
    if (_selectedPdfPath == null) return;

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
              Text('Сжатие PDF...'),
            ],
          ),
        ),
      );

      final compressedBytes = await PdfService.compressPdf(
        pdfPath: _selectedPdfPath!,
        qualityFactor: _qualityFactor,
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
            'PDF сжат на $reduction%\n'
            'Было: ${(originalSize / 1024).toStringAsFixed(2)}KB -> '
            '${(compressedSize / 1024).toStringAsFixed(2)}KB',
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
        title: const Text('Сжать PDF'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _pdfInfo == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Информация о PDF:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Имя файла:'),
                              Expanded(
                                child: Text(
                                  _pdfInfo!.fileName,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Размер:'),
                              Text('${_pdfInfo!.fileSizeMB} MB'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Страниц:'),
                              Text('${_pdfInfo!.pageCount}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Уровень сжатия:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<double>(
                    groupValue: _qualityFactor,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _qualityFactor = value);
                    },
                    child: Column(
                      children: const [
                        RadioListTile<double>(
                          title: Text('Максимальное качество'),
                          subtitle: Text('Минимальное сжатие (0.9)'),
                          value: 0.9,
                        ),
                        RadioListTile<double>(
                          title: Text('Хорошее качество'),
                          subtitle: Text('Среднее сжатие (0.7) - рекомендуется'),
                          value: 0.7,
                        ),
                        RadioListTile<double>(
                          title: Text('Среднее качество'),
                          subtitle: Text('Хорошее сжатие (0.5)'),
                          value: 0.5,
                        ),
                        RadioListTile<double>(
                          title: Text('Низкое качество'),
                          subtitle: Text('Максимальное сжатие (0.3)'),
                          value: 0.3,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: const Text(
                      'Сжатие происходит путём снижения качества изображений страниц PDF. '
                      'Текст останется читаемым, но качество графики может снизиться.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
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
                          onPressed: _isProcessing ? null : _compressAndSave,
                          icon: const Icon(Icons.compress),
                          label: const Text('Сжать и сохранить'),
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
    );
  }
}
