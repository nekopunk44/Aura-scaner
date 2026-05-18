import 'package:flutter/material.dart';
import 'dart:io';
import 'package:archive/archive.dart';
import 'dart:convert';

class DocxViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const DocxViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  State<DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<DocxViewerScreen> {
  String _fileContent = '';
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDocxContent();
  }

  Future<void> _loadDocxContent() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _fileContent = 'Файл не найден: ${widget.filePath}';
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final text = await _extractTextFromDocx(bytes);

      setState(() {
        _fileContent = text;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки DOCX: $e');
      setState(() {
        _fileContent = 'Ошибка загрузки файла: $e';
        _isLoading = false;
      });
    }
  }

  Future<String> _extractTextFromDocx(List<int> bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        return 'Не удалось найти текстовое содержимое в DOCX файле';
      }

      final xmlContent = utf8.decode(documentFile.content);
      return _parseWordXmlWithStructure(xmlContent);

    } catch (e) {
      return 'Ошибка обработки DOCX: $e';
    }
  }

  String _parseWordXmlWithStructure(String xmlContent) {
    try {
      final buffer = StringBuffer();

      // Разбиваем на параграфы
      final paragraphs = RegExp(r'<w:p[^>]*>.*?</w:p>', dotAll: true).allMatches(xmlContent);

      for (final paragraphMatch in paragraphs) {
        final paragraph = paragraphMatch.group(0)!;
        _processParagraph(paragraph, buffer);
      }

      return buffer.toString().trim();
    } catch (e) {
      return 'Ошибка парсинга структуры: $e';
    }
  }

  void _processParagraph(String paragraphXml, StringBuffer buffer) {
    try {
      if (paragraphXml.contains('<w:tbl>')) {
        _processTable(paragraphXml, buffer);
        return;
      }

      final textMatches = RegExp(r'<w:t[^>]*>([^<]+)</w:t>').allMatches(paragraphXml);
      final paragraphText = textMatches.map((m) => m.group(1)?.trim() ?? '').where((t) => t.isNotEmpty).join(' ');

      if (paragraphText.isNotEmpty) {
        final isHeading = _isHeadingParagraph(paragraphXml) || _isLikelyHeading(paragraphText);

        if (isHeading) {
          buffer.writeln('\n${paragraphText.toUpperCase()}');
          buffer.writeln('${'=' * paragraphText.length}\n');
        } else {
          buffer.writeln(paragraphText);
        }

        buffer.writeln();
      }
    } catch (e) {
      debugPrint('Ошибка обработки параграфа: $e');
    }
  }

  void _processTable(String tableXml, StringBuffer buffer) {
    try {
      final rows = RegExp(r'<w:tr[^>]*>.*?</w:tr>', dotAll: true).allMatches(tableXml);
      final tableData = <List<String>>[];

      for (final rowMatch in rows) {
        final row = rowMatch.group(0)!;
        final cells = RegExp(r'<w:tc[^>]*>.*?</w:tc>', dotAll: true).allMatches(row);
        final rowData = <String>[];

        for (final cellMatch in cells) {
          final cell = cellMatch.group(0)!;
          final textMatches = RegExp(r'<w:t[^>]*>([^<]+)</w:t>').allMatches(cell);
          final cellText = textMatches.map((m) => m.group(1)?.trim() ?? '').where((t) => t.isNotEmpty).join(' ');
          rowData.add(cellText);
        }

        if (rowData.any((cell) => cell.isNotEmpty)) {
          tableData.add(rowData);
        }
      }

      if (tableData.isNotEmpty) {
        _formatTable(tableData, buffer);
      }
    } catch (e) {
      debugPrint('Ошибка обработки таблицы: $e');
    }
  }

  void _formatTable(List<List<String>> tableData, StringBuffer buffer) {
    if (tableData.isEmpty) return;

    final columnWidths = List<int>.filled(tableData[0].length, 0);
    for (final row in tableData) {
      for (int i = 0; i < row.length; i++) {
        if (i < columnWidths.length) {
          columnWidths[i] = columnWidths[i] > row[i].length ? columnWidths[i] : row[i].length;
        }
      }
    }

    for (int i = 0; i < columnWidths.length; i++) {
      columnWidths[i] = columnWidths[i] > 30 ? 30 : columnWidths[i];
    }

    buffer.writeln('\n┌${_generateTableLine(columnWidths, '─', '┬')}┐');

    for (int i = 0; i < tableData.length; i++) {
      final row = tableData[i];
      buffer.write('│');

      for (int j = 0; j < columnWidths.length; j++) {
        final cellText = j < row.length ? row[j] : '';
        final width = columnWidths[j];
        final paddedText = cellText.length > width ? '${cellText.substring(0, width - 1)}…' : cellText.padRight(width);
        buffer.write(' $paddedText │');
      }

      buffer.writeln();

      if (i == 0) {
        buffer.writeln('├${_generateTableLine(columnWidths, '─', '┼')}┤');
      } else if (i == tableData.length - 1) {
        buffer.writeln('└${_generateTableLine(columnWidths, '─', '┴')}┘');
      }
    }

    buffer.writeln();
  }

  String _generateTableLine(List<int> widths, String lineChar, String junction) {
    return widths.map((w) => lineChar * (w + 2)).join(junction);
  }

  bool _isHeadingParagraph(String paragraphXml) {
    return paragraphXml.contains('w:val="Heading') ||
        paragraphXml.contains('w:val="Title') ||
        paragraphXml.contains('Heading');
  }

  bool _isLikelyHeading(String text) {
    if (text.isEmpty) return false;

    return text.length < 100 &&
        (text.toUpperCase() == text ||
            text.endsWith(':') ||
            RegExp(r'^[A-ZА-Я][^.!?]*[.:]?$').hasMatch(text) ||
            text.split(' ').length <= 5);
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        actions: [
          if (!_isLoading && _fileContent.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.vertical_align_top),
              tooltip: 'В начало',
              onPressed: _scrollToTop,
            ),
            IconButton(
              icon: const Icon(Icons.vertical_align_bottom),
              tooltip: 'В конец',
              onPressed: _scrollToBottom,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Обработка документа...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      )
          : _fileContent.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Документ пуст',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      )
          : Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                border: Border(
                  bottom: BorderSide(color: Colors.green[300]!),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Документ загружен. Таблицы и структура сохранены.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _fileContent,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.black87,
                      fontFamily: 'Courier',
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}