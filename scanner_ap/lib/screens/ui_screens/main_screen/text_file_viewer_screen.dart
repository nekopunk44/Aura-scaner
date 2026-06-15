import 'package:flutter/material.dart';
import 'dart:io';
import '../../../l10n/app_localizations.dart';

class TextFileViewerScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const TextFileViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  State<TextFileViewerScreen> createState() => _TextFileViewerScreenState();
}

class _TextFileViewerScreenState extends State<TextFileViewerScreen> {
  String _fileContent = '';
  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  Future<void> _loadFileContent() async {
    try {
      final file = File(widget.filePath);
      final content = await file.readAsString();
      setState(() {
        _fileContent = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(widget.fileName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: const Color(0xFF2CA5E0)))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: SelectableText(
                  _loadError != null
                      ? '${AppLocalizations.of(context).fileLoadError}: $_loadError'
                      : _fileContent,
                  style: TextStyle(fontSize: 15, height: 1.6, color: textColor),
                ),
              ),
            ),
    );
  }
}