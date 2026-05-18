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
import 'package:shared_preferences/shared_preferences.dart';

import '../main_screen/docx_viewer_screen.dart';
import '../main_screen/pdf_viewer_screen.dart';
import '../main_screen/text_file_viewer_screen.dart';
import '../photo_view_screen.dart';

const _documentKey = 'saved_document_paths';

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

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_documentKey) ?? [];
    if (!paths.contains(destPath)) {
      paths.add(destPath);
      await prefs.setStringList(_documentKey, paths);
    }

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Импорт документа'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        actions: [
          if (_selectedPath != null && !_isImporting)
            TextButton(
              onPressed: _confirmImport,
              child: const Text('Импортировать'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedPath != null) ...[
              Card(
                child: ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                  title: Text(p.basename(_selectedPath!)),
                  subtitle: const Text('Выбранный файл'),
                  trailing: _isImporting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _selectedPath = null),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isImporting ? null : _confirmImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isImporting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Импортировать',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isImporting ? null : _importAndOpenEditor,
                icon: const Icon(Icons.edit_document),
                label: const Text('Импортировать и открыть редактор'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(Icons.folder_open, size: 72, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Выберите файл для импорта',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            const Text(
              'Выбрать файл',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            _PickButton(
              icon: Icons.picture_as_pdf,
              label: 'PDF документ',
              color: Colors.red,
              enabled: !_isPicking && !_isImporting,
              onTap: () => _pickFile(extensions: ['pdf']),
            ),
            const SizedBox(height: 10),
            _PickButton(
              icon: Icons.description,
              label: 'Word / TXT документ',
              color: Colors.blue,
              enabled: !_isPicking && !_isImporting,
              onTap: () => _pickFile(extensions: ['docx', 'doc', 'txt']),
            ),
            const SizedBox(height: 10),
            _PickButton(
              icon: Icons.image,
              label: 'Изображение',
              color: Colors.green,
              enabled: !_isPicking && !_isImporting,
              onTap: () => _pickFile(extensions: ['jpg', 'jpeg', 'png']),
            ),
            const SizedBox(height: 10),
            _PickButton(
              icon: Icons.folder,
              label: 'Любой файл',
              color: Colors.orange,
              enabled: !_isPicking && !_isImporting,
              onTap: () => _pickFile(extensions: null),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _PickButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, color: enabled ? color : Colors.grey),
      label: Text(
        label,
        style: TextStyle(color: enabled ? Colors.black87 : Colors.grey),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        side: BorderSide(color: enabled ? color : Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        alignment: Alignment.centerLeft,
      ),
      onPressed: enabled ? onTap : null,
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(filePath: _currentPath, fileName: _fileName),
        ),
      );
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

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      final index = paths.indexOf(_currentPath);
      if (index != -1) {
        paths[index] = newPath;
        await prefs.setStringList(_documentKey, paths);
      }

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

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      paths.remove(_currentPath);
      await prefs.setStringList(_documentKey, paths);

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
