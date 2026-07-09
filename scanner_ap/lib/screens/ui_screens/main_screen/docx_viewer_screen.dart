import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

import '../../../l10n/app_localizations.dart';

/// Извлечение текста из DOCX. Выполняется в изоляте (compute) — большие
/// документы разбираются секунды, и UI-поток не блокируется. Парсинг через
/// package:xml (линейный), а не регэкспами по всему документу: старый
/// вариант `<w:p>.*?</w:p>` с dotAll на больших файлах давал квадратичную
/// сложность и «вечную» обработку.
///
/// Возвращает null, если внутри архива нет word/document.xml.
String? extractDocxPlainText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final documentFile = archive.findFile('word/document.xml');
  if (documentFile == null) return null;

  final xmlContent =
      utf8.decode(documentFile.content as List<int>, allowMalformed: true);
  final doc = XmlDocument.parse(xmlContent);
  final body = doc.rootElement.getElement('w:body');
  if (body == null) return '';

  final buffer = StringBuffer();
  for (final node in body.childElements) {
    switch (node.name.local) {
      case 'p':
        _writeParagraph(node, buffer);
        break;
      case 'tbl':
        _writeTable(node, buffer);
        break;
    }
  }
  return buffer.toString().trim();
}

String _elementText(XmlElement scope) {
  return scope
      .findAllElements('w:t')
      .map((t) => t.innerText)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

void _writeParagraph(XmlElement paragraph, StringBuffer buffer) {
  final text = _elementText(paragraph);
  if (text.isEmpty) return;

  final isHeading = _isHeadingParagraph(paragraph) || _isLikelyHeading(text);
  if (isHeading) {
    buffer.writeln('\n${text.toUpperCase()}');
    buffer.writeln('${'=' * text.length}\n');
  } else {
    buffer.writeln(text);
  }
  buffer.writeln();
}

bool _isHeadingParagraph(XmlElement paragraph) {
  for (final style in paragraph.findAllElements('w:pStyle')) {
    final val = style.getAttribute('w:val') ?? '';
    if (val.startsWith('Heading') || val.startsWith('Title')) return true;
  }
  return false;
}

bool _isLikelyHeading(String text) {
  if (text.isEmpty) return false;
  return text.length < 100 &&
      (text.toUpperCase() == text ||
          text.endsWith(':') ||
          RegExp(r'^[A-ZА-Я][^.!?]*[.:]?$').hasMatch(text) ||
          text.split(' ').length <= 5);
}

void _writeTable(XmlElement table, StringBuffer buffer) {
  final tableData = <List<String>>[];
  for (final row in table.findElements('w:tr')) {
    final rowData = <String>[
      for (final cell in row.findElements('w:tc')) _elementText(cell),
    ];
    if (rowData.any((cell) => cell.isNotEmpty)) {
      tableData.add(rowData);
    }
  }
  if (tableData.isNotEmpty) {
    _formatTable(tableData, buffer);
  }
}

void _formatTable(List<List<String>> tableData, StringBuffer buffer) {
  if (tableData.isEmpty) return;

  final columnCount =
      tableData.map((row) => row.length).reduce((a, b) => a > b ? a : b);
  final columnWidths = List<int>.filled(columnCount, 0);
  for (final row in tableData) {
    for (int i = 0; i < row.length; i++) {
      columnWidths[i] =
          columnWidths[i] > row[i].length ? columnWidths[i] : row[i].length;
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
      final paddedText = cellText.length > width
          ? '${cellText.substring(0, width - 1)}…'
          : cellText.padRight(width);
      buffer.write(' $paddedText │');
    }

    buffer.writeln();

    if (i == 0 && tableData.length > 1) {
      buffer.writeln('├${_generateTableLine(columnWidths, '─', '┼')}┤');
    }
  }
  buffer.writeln('└${_generateTableLine(columnWidths, '─', '┴')}┘');
  buffer.writeln();
}

String _generateTableLine(List<int> widths, String lineChar, String junction) {
  return widths.map((w) => lineChar * (w + 2)).join(junction);
}

class DocxViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const DocxViewerScreen(
      {super.key, required this.filePath, required this.fileName});

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
    // Захватываем l10n до await — context гарантированно валиден здесь.
    final l10n = AppLocalizations.of(context);
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _fileContent = l10n.docFileNotFoundNamed(widget.filePath);
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      // Распаковка и парсинг — в изоляте, UI-поток свободен.
      final text = await compute(extractDocxPlainText, bytes);

      if (!mounted) return;
      setState(() {
        _fileContent = text ?? l10n.docxNoTextContent;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки DOCX: $e');
      if (!mounted) return;
      setState(() {
        _fileContent = '${l10n.fileLoadError}: $e';
        _isLoading = false;
      });
    }
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
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg =
        isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final bannerBg = isDark
        ? Colors.green.shade900.withValues(alpha: 0.4)
        : Colors.green.shade50;
    final bannerBorder =
        isDark ? Colors.green.shade800 : Colors.green.shade300;
    final bannerText = isDark ? Colors.green.shade300 : Colors.green.shade700;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(widget.fileName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        actions: [
          if (!_isLoading && _fileContent.isNotEmpty) ...[
            IconButton(
                icon: Icon(Icons.vertical_align_top, color: textColor),
                tooltip: l10n.tooltipToTop,
                onPressed: _scrollToTop),
            IconButton(
                icon: Icon(Icons.vertical_align_bottom, color: textColor),
                tooltip: l10n.tooltipToBottom,
                onPressed: _scrollToBottom),
          ],
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF2CA5E0)),
                  const SizedBox(height: 16),
                  Text(l10n.docxProcessing,
                      style: TextStyle(fontSize: 15, color: subColor)),
                ],
              ),
            )
          : _fileContent.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description, size: 64, color: subColor),
                      const SizedBox(height: 16),
                      Text(l10n.docxEmpty,
                          style: TextStyle(fontSize: 18, color: subColor)),
                    ],
                  ),
                )
              : Container(
                  color: scaffoldBg,
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: bannerBg,
                          border:
                              Border(bottom: BorderSide(color: bannerBorder)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: bannerText, size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.docxLoadedNote,
                                style:
                                    TextStyle(fontSize: 12, color: bannerText),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: cardBg,
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                _fileContent,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: textColor,
                                  fontFamily: 'monospace',
                                ),
                              ),
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
