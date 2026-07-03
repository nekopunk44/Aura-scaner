import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../services/document_registry.dart';
import '../main_screen/docx_viewer_screen.dart';
import '../main_screen/pdf_viewer_screen.dart';
import '../main_screen/text_file_viewer_screen.dart';
import '../photo_view_screen.dart';
import '../signature/image_signature_editor_screen.dart';

class DocumentImporter extends StatefulWidget {
  final String? initialPath;
  final void Function(String path) onConfirm;
  final void Function() onBack;

  const DocumentImporter({
    super.key,
    this.initialPath,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  State<DocumentImporter> createState() => _DocumentImporterState();
}

class _DocumentImporterState extends State<DocumentImporter> {
  String? _selectedPath;
  bool _isPicking = false;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialPath;
  }

  Future<void> _pickFile({required List<String>? extensions}) async {
    setState(() => _isPicking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: extensions != null ? FileType.custom : FileType.any,
        allowedExtensions: extensions,
        allowMultiple: false,
      );
      if (result != null && result.files.first.path != null) {
        setState(() => _selectedPath = result.files.first.path!);
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<String?> _importSelectedFile() async {
    if (_selectedPath == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(_selectedPath!);
    final destPath = '${dir.path}/$fileName';

    if (_selectedPath != destPath) {
      await File(_selectedPath!).copy(destPath);
    }

    await DocumentRegistry().load();
    await DocumentRegistry().add(
      DocEntry(
        localPath: destPath,
        remoteId: null,
        name: p.basenameWithoutExtension(destPath),
      ),
    );

    return destPath;
  }

  Future<void> _confirmImport() async {
    if (_selectedPath == null) return;
    setState(() => _isImporting = true);

    try {
      final destPath = await _importSelectedFile();
      if (destPath != null && mounted) {
        widget.onConfirm(destPath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _importAndOpenEditor() async {
    if (_selectedPath == null) return;
    setState(() => _isImporting = true);

    try {
      final destPath = await _importSelectedFile();
      if (destPath == null || !mounted) return;

      final editedPath = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditorScreen(filePath: destPath),
        ),
      );

      if (!mounted) return;
      if (editedPath == '') return;
      widget.onConfirm(editedPath ?? destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
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
    const accent = Color(0xFF2CA5E0);

    final enabled = !_isPicking && !_isImporting;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          'Импорт документа',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selectedPath != null) ...[
                _SelectedFileCard(
                  path: _selectedPath!,
                  isImporting: _isImporting,
                  cardBg: cardBg,
                  textColor: textColor,
                  subColor: subColor,
                  accent: accent,
                  onClear: () => setState(() => _selectedPath = null),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isImporting ? null : _importAndOpenEditor,
                        icon: const Icon(Icons.edit_document, size: 18),
                        label: const Text('Редактор'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: const BorderSide(color: accent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isImporting ? null : _confirmImport,
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: const Text('Импортировать'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          disabledBackgroundColor: accent.withValues(alpha: 0.4),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        width: 96, height: 96,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.folder_open_outlined,
                          size: 48,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Откройте документ из памяти',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Выберите тип файла, чтобы открыть проводник',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: subColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'ВЫБОР ТИПА ФАЙЛА',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: subColor,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.05,
                children: [
                  _PickCard(
                    icon: Icons.picture_as_pdf,
                    label: 'PDF',
                    description: 'Документы и книги',
                    color: const Color(0xFFE74C3C),
                    enabled: enabled,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickFile(extensions: ['pdf']),
                  ),
                  _PickCard(
                    icon: Icons.description_outlined,
                    label: 'Word / TXT',
                    description: 'Тексты, отчёты',
                    color: const Color(0xFF3498DB),
                    enabled: enabled,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickFile(extensions: ['docx', 'doc', 'txt']),
                  ),
                  _PickCard(
                    icon: Icons.photo_outlined,
                    label: 'Изображение',
                    description: 'JPG, PNG',
                    color: const Color(0xFF27AE60),
                    enabled: enabled,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickFile(extensions: ['jpg', 'jpeg', 'png']),
                  ),
                  _PickCard(
                    icon: Icons.table_chart_outlined,
                    label: 'Excel / PowerPoint',
                    description: 'Таблицы, презентации',
                    color: const Color(0xFF107C41),
                    enabled: enabled,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () =>
                        _pickFile(extensions: ['xlsx', 'xls', 'pptx', 'ppt']),
                  ),
                  _PickCard(
                    icon: Icons.folder_outlined,
                    label: 'Любой файл',
                    description: 'Открыть проводник',
                    color: const Color(0xFFE67E22),
                    enabled: enabled,
                    cardBg: cardBg,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: () => _pickFile(extensions: null),
                  ),
                ],
              ),
              if (_isPicking) ...[
                const SizedBox(height: 18),
                const Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedFileCard extends StatelessWidget {
  final String path;
  final bool isImporting;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  final Color accent;
  final VoidCallback onClear;

  const _SelectedFileCard({
    required this.path,
    required this.isImporting,
    required this.cardBg,
    required this.textColor,
    required this.subColor,
    required this.accent,
    required this.onClear,
  });

  IconData _iconFor(String ext) {
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
      case '.txt':
        return Icons.description_outlined;
      case '.jpg':
      case '.jpeg':
      case '.png':
        return Icons.photo_outlined;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart_outlined;
      case '.ppt':
      case '.pptx':
        return Icons.slideshow_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorFor(String ext) {
    switch (ext) {
      case '.pdf':
        return const Color(0xFFE74C3C);
      case '.doc':
      case '.docx':
      case '.txt':
        return const Color(0xFF3498DB);
      case '.jpg':
      case '.jpeg':
      case '.png':
        return const Color(0xFF27AE60);
      case '.xls':
      case '.xlsx':
        return const Color(0xFF107C41);
      case '.ppt':
      case '.pptx':
        return const Color(0xFFC43E1C);
      default:
        return const Color(0xFFE67E22);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).toLowerCase();
    final fileColor = _colorFor(ext);
    final fileIcon = _iconFor(ext);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: fileColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(fileIcon, color: fileColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Готов к импорту',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ],
            ),
          ),
          isImporting
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: Icon(Icons.close, color: subColor, size: 22),
                  onPressed: onClear,
                ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final bool enabled;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  final VoidCallback onTap;

  const _PickCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.enabled,
    required this.cardBg,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: subColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DocumentEditorScreen extends StatefulWidget {
  final String filePath;

  const DocumentEditorScreen({super.key, required this.filePath});

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {
  late String _currentPath;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.filePath;
  }

  String get _fileName => p.basename(_currentPath);
  String get _extension => p.extension(_currentPath).toLowerCase();
  bool get _isImage => ['.jpg', '.jpeg', '.png'].contains(_extension);
  bool get _isPdf => _extension == '.pdf';
  bool get _isDoc => ['.doc', '.docx'].contains(_extension);
  bool get _isText => _extension == '.txt';

  void _closeEditor([String? result]) {
    Navigator.pop(context, result ?? _currentPath);
  }

  Future<void> _openDocument() async {
    if (_isImage) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewScreen(imagePath: _currentPath, title: _fileName),
        ),
      );
      return;
    }

    if (_isPdf) {
      final result = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(filePath: _currentPath, fileName: _fileName),
        ),
      );
      if (!mounted || result == null || result.isEmpty) return;
      setState(() => _currentPath = result);
      return;
    }

    if (_isDoc) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocxViewerScreen(filePath: _currentPath, fileName: _fileName),
        ),
      );
      return;
    }

    if (_isText) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextFileViewerScreen(filePath: _currentPath, fileName: _fileName),
        ),
      );
      return;
    }

    final result = await OpenFilex.open(_currentPath);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть файл: ${result.message}')),
      );
    }
  }

  Future<void> _shareDocument() async {
    await Share.shareXFiles([XFile(_currentPath)], subject: _fileName);
  }

  Future<void> _renameDocument() async {
    final dotIndex = _fileName.lastIndexOf('.');
    final baseName = dotIndex == -1 ? _fileName : _fileName.substring(0, dotIndex);
    final extension = dotIndex == -1 ? '' : _fileName.substring(dotIndex);
    final controller = TextEditingController(text: baseName);

    final newBaseName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Переименовать документ'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: baseName,
              helperText: extension.isEmpty ? null : 'Расширение сохранится: $extension',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (newBaseName == null || newBaseName.isEmpty) return;

    final newPath = p.join(p.dirname(_currentPath), '$newBaseName$extension');
    if (newPath == _currentPath) return;

    setState(() => _isBusy = true);
    try {
      await File(_currentPath).rename(newPath);

      await DocumentRegistry().load();
      await DocumentRegistry().updateLocalPath(
        _currentPath,
        newPath,
        newBaseName,
      );

      if (!mounted) return;
      setState(() => _currentPath = newPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Документ переименован в ${p.basename(newPath)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка переименования: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _deleteDocument() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить документ'),
          content: Text('Удалить $_fileName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isBusy = true);
    try {
      final file = File(_currentPath);
      if (await file.exists()) {
        await file.delete();
      }

      await DocumentRegistry().load();
      await DocumentRegistry().remove(_currentPath);

      if (!mounted) return;
      Navigator.pop(context, '');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _cropImage() async {
    if (!_isImage) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: _currentPath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Обрезать изображение',
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
      ],
    );

    if (cropped == null) return;

    setState(() => _isBusy = true);
    try {
      final bytes = await File(cropped.path).readAsBytes();
      await File(_currentPath).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изображение обновлено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка обрезки: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _rotateImage() async {
    if (!_isImage) return;

    setState(() => _isBusy = true);
    try {
      final bytes = await File(_currentPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Не удалось декодировать изображение');
      }

      final rotated = img.copyRotate(decoded, angle: 90);
      final Uint8List outputBytes;
      if (_extension == '.png') {
        outputBytes = Uint8List.fromList(img.encodePng(rotated));
      } else {
        outputBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
      }

      await File(_currentPath).writeAsBytes(outputBytes, flush: true);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изображение повернуто')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка поворота: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _signImage() async {
    if (!_isImage) return;

    final previousPath = _currentPath;
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageSignatureEditorScreen(
          filePath: _currentPath,
          fileName: _fileName,
        ),
      ),
    );

    if (!mounted || result == null || result.isEmpty) return;

    setState(() => _isBusy = true);
    try {
      await DocumentRegistry().load();
      await DocumentRegistry().updateLocalPath(
        previousPath,
        result,
        p.basenameWithoutExtension(result),
      );

      if (!mounted) return;
      setState(() => _currentPath = result);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подпись добавлена в документ')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка подписи: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Widget _buildPreview() {
    if (_isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(_currentPath),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 72),
        ),
      );
    }

    final icon = _isPdf
        ? Icons.picture_as_pdf
        : _isDoc
            ? Icons.description
            : _isText
                ? Icons.text_snippet
                : Icons.insert_drive_file;

    final color = _isPdf
        ? Colors.red
        : _isDoc
            ? Colors.blue
            : _isText
                ? Colors.teal
                : Colors.orange;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageTools() {
    if (!_isImage) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Инструменты изображения',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _cropImage,
                icon: const Icon(Icons.crop),
                label: const Text('Обрезать'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _rotateImage,
                icon: const Icon(Icons.rotate_right),
                label: const Text('Повернуть'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isBusy ? null : _signImage,
            icon: const Icon(Icons.draw_outlined),
            label: const Text('Добавить подпись'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeEditor();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Редактор документа'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _closeEditor,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1.15,
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildPreview()),
                    if (_isBusy)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x66000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentPath,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isBusy ? null : _openDocument,
                icon: const Icon(Icons.visibility),
                label: Text(_isImage ? 'Открыть просмотр' : 'Открыть документ'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _shareDocument,
                      icon: const Icon(Icons.share),
                      label: const Text('Поделиться'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _renameDocument,
                      icon: const Icon(Icons.edit),
                      label: const Text('Переименовать'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildImageTools(),
              if (_isImage) const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _deleteDocument,
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('Удалить документ'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
