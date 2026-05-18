//Главный экран хранилища документов.
//
//Отображает список всех сохранённых файлов с превью-миниатюрами.
//Пути к файлам хранятся в SharedPreferences по ключу 'documents'.
//
//Поддерживаемые форматы: PDF, DOCX, DOC, TXT, JPG, JPEG, PNG.
//
//Операции с файлами:
//- Просмотр (открывает подходящий viewer)
//- Переименование (диалог с текстовым полем)
//- Удаление (с подтверждением, удаляет файл с диска)
//- Экспорт (в галерею для изображений, через FilePicker для остальных)
//
//Превью генерируются асинхронно через миксин DocumentUtils и кэшируются.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/document_sync_service.dart';
import '../../../services/document_registry.dart';
import 'pdf_viewer_screen.dart';
import 'docx_viewer_screen.dart';
import 'text_file_viewer_screen.dart';
import 'document_utils.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => MyDocumentsScreenState();
}

class MyDocumentsScreenState extends State<MyDocumentsScreen>
    with AutomaticKeepAliveClientMixin, DocumentUtils {

  @override
  bool get wantKeepAlive => true;

  void refreshDocuments() => _loadDocuments();

  final List<String> _documentPaths = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  final List<String> _filteredDocumentPaths = [];
  bool _isSearching = false;

  final Map<String, Future<Uint8List?>> _previewFutures = {};

  @override
  void initState() {
    super.initState();
    _loadDocuments();

    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredDocumentPaths.clear();
      });
    } else {
      setState(() {
        _isSearching = true;
        _filteredDocumentPaths.clear();
        _filteredDocumentPaths.addAll(
            _documentPaths.where((path) {
              final fileName = getFileNameFromPath(path).toLowerCase();
              return fileName.contains(query);
            })
        );
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _filteredDocumentPaths.clear();
    });
  }

  List<String> get _displayedDocumentPaths {
    return _isSearching ? _filteredDocumentPaths : _documentPaths;
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);

    final registry = DocumentRegistry();
    await registry.load();

    // Сначала показываем локальные файлы
    final localEntries = registry.entries
        .where((e) => File(e.localPath).existsSync())
        .toList();

    if (mounted) {
      setState(() {
        _documentPaths
          ..clear()
          ..addAll(localEntries.map((e) => e.localPath));
        _isLoading = false;
      });
    }

    // Фоновая синхронизация с облаком
    _syncWithCloud(registry);
  }

  Future<void> _syncWithCloud(DocumentRegistry registry) async {
    try {
      final remoteList = await DocumentSyncService().list();
      final localRemoteIds = registry.entries
          .map((e) => e.remoteId)
          .whereType<String>()
          .toSet();

      // Скачиваем облачные документы, которых нет локально
      for (final remote in remoteList) {
        if (!localRemoteIds.contains(remote.id)) {
          await _downloadAndRegister(remote, registry);
        }
      }

      // Повторяем загрузку для файлов без remoteId (failed upload)
      for (final entry in registry.entries.where((e) =>
          e.remoteId == null && File(e.localPath).existsSync())) {
        _retryUpload(entry);
      }

      // Обновляем список после скачивания
      await registry.load();
      final updatedEntries = registry.entries
          .where((e) => File(e.localPath).existsSync())
          .toList();

      if (!mounted) return;
      setState(() {
        _documentPaths
          ..clear()
          ..addAll(updatedEntries.map((e) => e.localPath));
      });
    } catch (_) {
      // Оффлайн — работаем с локальными файлами
    }
  }

  Future<void> _downloadAndRegister(
      RemoteDocument remote, DocumentRegistry registry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      var finalPath = '${dir.path}/${remote.name}.${remote.format}';
      var counter = 1;
      while (File(finalPath).existsSync()) {
        finalPath = '${dir.path}/${remote.name}_$counter.${remote.format}';
        counter++;
      }
      await DocumentSyncService().download(remote.id, finalPath);
      await registry.add(DocEntry(
        localPath: finalPath,
        remoteId: remote.id,
        name: remote.name,
      ));
    } catch (e) {
      debugPrint('Download failed for ${remote.id}: $e');
    }
  }

  void _retryUpload(DocEntry entry) {
    () async {
      try {
        final remote = await DocumentSyncService()
            .upload(File(entry.localPath), name: entry.name);
        await DocumentRegistry().updateRemoteId(entry.localPath, remote.id);
      } catch (e) {
        debugPrint('Retry upload failed: $e');
      }
    }();
  }

  Future<Uint8List?> _loadPreviewFuture(String filePath) async {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    try {
      if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') || fileName.endsWith('.png')) {
        return await File(filePath).readAsBytes();
      } else if (fileName.endsWith('.pdf')) {
        return await generatePdfPreview(filePath);
      } else if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
        return await generateDocxPreview(filePath);
      } else if (fileName.endsWith('.txt')) {
        final content = await File(filePath).readAsString();
        return await _createTextPreview(content);
      }
      // fallback: пробуем прочитать как изображение (файл без расширения)
      try {
        return await File(filePath).readAsBytes();
      } catch (_) {
        return null;
      }
    } catch (e) {
      debugPrint('Ошибка загрузки превью для $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _createTextPreview(String content) async {
    try {
      final text = content.length > 100
          ? '${content.substring(0, 100)}...'
          : content;
      return await _textToImage(text);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _textToImage(String text) async {
    const double w = 150;
    const double h = 150;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFF5F5F5),
    );

    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: 10,
      textDirection: TextDirection.ltr,
    ))
      ..pushStyle(ui.TextStyle(color: const Color(0xFF333333), fontSize: 10))
      ..addText(text);

    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: w - 8));
    canvas.drawParagraph(paragraph, const Offset(4, 4));

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Widget _buildFilePreview(String filePath) {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    final future = _previewFutures.putIfAbsent(filePath, () => _loadPreviewFuture(filePath));

    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final previewBytes = snapshot.data;
        if (previewBytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.memory(
                previewBytes,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFileIcon(fileName),
              ),
            ),
          );
        }

        return _buildFileIcon(fileName);
      },
    );
  }

  Widget _buildFileIcon(String fileName) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: _getFileColor(fileName),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          _getFileIcon(fileName),
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Color _getFileColor(String fileName) {
    if (fileName.endsWith('.pdf')) return Colors.red;
    if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) return Colors.blue;
    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png')) {
      return Colors.green;
    }
    if (fileName.endsWith('.txt')) return Colors.grey;
    return Colors.orange;
  }

  IconData _getFileIcon(String fileName) {
    if (fileName.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) return Icons.description;
    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png')) {
      return Icons.image;
    }
    if (fileName.endsWith('.txt')) return Icons.text_fields;
    return Icons.insert_drive_file;
  }

  void _exportDocument(String fullPath) async {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    if (!(await _requestPermissions())) {
      return;
    }

    final fileToExport = File(fullPath);
    final fileName = getFileNameFromPath(fullPath);
    final lowerCaseFileName = fileName.toLowerCase();
    String destination = '';
    bool success = false;

    try {
      if (!await fileToExport.exists()) {
        throw Exception('Файл не найден по пути: $fullPath');
      }

      if (lowerCaseFileName.endsWith('.jpg') ||
          lowerCaseFileName.endsWith('.png') ||
          lowerCaseFileName.endsWith('.jpeg')) {
        final bytes = await fileToExport.readAsBytes();
        final result = await ImageGallerySaverPlus.saveImage(
            bytes, name: fileName);

        if (result is Map &&
            (result['isSuccess'] == true || result['isSuccess'] == 1)) {
          destination = 'Галерее';
          success = true;
        } else if (result == true) {
          destination = 'Галерее';
          success = true;
        } else {
          throw Exception('Не удалось сохранить фото в Галерею.');
        }
      } else {
        final Uint8List fileBytes = await fileToExport.readAsBytes();
        final String? newPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: fileBytes,
        );

        if (newPath != null) {
          destination = 'в выбранной папке';
          success = true;
        } else {
          throw Exception('Сохранение отменено пользователем или не удалось.');
        }
      }

      if (mounted && success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Файл "$fileName" успешно сохранен в $destination.'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Ошибка сохранения файла "$fileName": ${e.toString()}'),
            duration: const Duration(seconds: 7),
          ),
        );
      }
    }
  }

  void _deleteDocument(int index) {
    String filePath;
    if (_isSearching) {
      filePath = _filteredDocumentPaths[index];
      final originalIndex = _documentPaths.indexOf(filePath);
      _documentPaths.removeAt(originalIndex);
      _filteredDocumentPaths.removeAt(index);
    } else {
      filePath = _documentPaths[index];
      _documentPaths.removeAt(index);
    }

    final fileName = getFileNameFromPath(filePath);
    _previewFutures.remove(filePath);

    setState(() {});

    // Удаляем локальный файл
    try {
      File(filePath).deleteSync();
    } catch (e) {
      debugPrint('Ошибка удаления файла с диска: $e');
    }

    // Удаляем из реестра и с сервера
    () async {
      final remoteId = DocumentRegistry().getRemoteId(filePath);
      await DocumentRegistry().remove(filePath);
      if (remoteId != null) {
        try {
          await DocumentSyncService().delete(remoteId);
        } catch (e) {
          debugPrint('Cloud delete failed: $e');
        }
      }
    }();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Документ "$fileName" удалён.')),
      );
    }
  }

  void _renameDocument(int index) {
    if (!mounted) return;

    String currentPath;
    int originalIndex;

    if (_isSearching) {
      currentPath = _filteredDocumentPaths[index];
      originalIndex = _documentPaths.indexOf(currentPath);
    } else {
      currentPath = _documentPaths[index];
      originalIndex = index;
    }

    final currentFullName = getFileNameFromPath(currentPath);

    String fileName = currentFullName;
    String? fileExtension;

    final lastDotIndex = currentFullName.lastIndexOf('.');
    if (lastDotIndex != -1) {
      fileName = currentFullName.substring(0, lastDotIndex);
      fileExtension = currentFullName.substring(lastDotIndex);
    }

    final controller = TextEditingController(text: fileName);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Переименовать файл'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(hintText: fileName),
                autofocus: true,
              ),
              if (fileExtension != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Расширение: $fileExtension',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final dialogMessenger = ScaffoldMessenger.of(context);
                final dialogNavigator = Navigator.of(context);
                String newBaseName = controller.text.trim();
                if (newBaseName.isEmpty) {
                  dialogMessenger.showSnackBar(
                    const SnackBar(
                        content: Text('Имя файла не может быть пустым.')),
                  );
                  return;
                }

                if (fileExtension != null && newBaseName.toLowerCase().endsWith(
                    fileExtension.toLowerCase())) {
                  newBaseName = newBaseName.substring(
                      0, newBaseName.length - fileExtension.length);
                }

                final newFullName = newBaseName + (fileExtension ?? '');

                if (newFullName == currentFullName) {
                  dialogNavigator.pop();
                  return;
                }

                final newPath = currentPath.replaceAll(
                    currentFullName, newFullName);

                try {
                  if (await File(newPath).exists()) {
                    if (mounted) {
                      dialogMessenger.showSnackBar(
                        SnackBar(content: Text(
                            'Ошибка переименования: Файл "$newFullName" уже существует.')),
                      );
                    }
                    dialogNavigator.pop();
                    return;
                  }

                  await File(currentPath).rename(newPath);

                  // Обновляем реестр
                  await DocumentRegistry().updateLocalPath(currentPath, newPath, newBaseName);

                  // Переименовываем на сервере если есть remoteId
                  final remoteId = DocumentRegistry().getRemoteId(newPath);
                  if (remoteId != null) {
                    try {
                      await DocumentSyncService().rename(remoteId, newBaseName);
                    } catch (e) {
                      debugPrint('Cloud rename failed: $e');
                    }
                  }

                  final future = _previewFutures.remove(currentPath);
                  if (future != null) _previewFutures[newPath] = future;

                  setState(() {
                    _documentPaths[originalIndex] = newPath;
                    if (_isSearching) {
                      _filteredDocumentPaths[index] = newPath;
                    }
                  });

                  if (mounted) {
                    dialogMessenger.showSnackBar(
                      SnackBar(
                          content: Text('Файл переименован в "$newFullName".')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    dialogMessenger.showSnackBar(
                      SnackBar(content: Text('Ошибка переименования: $e')),
                    );
                  }
                }
                dialogNavigator.pop();
              },
              child: const Text('Переименовать'),
            ),
          ],
        );
      },
    );
  }

  void _showDocumentMenu(BuildContext context, int index) {
    final fullPath = _isSearching
        ? _filteredDocumentPaths[index]
        : _documentPaths[index];
    final fileName = getFileNameFromPath(fullPath);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F0FF),
                    child: Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                  ),
                  title: const Text('Переименовать'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameDocument(index);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.save_alt, color: Colors.green, size: 20),
                  ),
                  title: const Text('Сохранить / Экспорт'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportDocument(fullPath);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.share_outlined, color: Colors.orange, size: 20),
                  ),
                  title: const Text('Поделиться'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareDocument(fullPath);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFEBEE),
                    child: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  ),
                  title: const Text('Удалить',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmAndDelete(index);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndDelete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить файл?'),
        content: const Text('Файл будет удалён без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) _deleteDocument(index);
  }

  Future<void> _shareDocument(String fullPath) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = File(fullPath);
    if (!await file.exists()) {
      messenger.showSnackBar(const SnackBar(content: Text('Файл не найден')));
      return;
    }
    final fileName = getFileNameFromPath(fullPath);
    await Share.shareXFiles(
      [XFile(fullPath)],
      subject: fileName,
    );
  }

  void _addDocument(String fullPath) {
    if (_documentPaths.contains(fullPath)) return;

    setState(() {
      _documentPaths.add(fullPath);
      if (_isSearching) {
        final query = _searchController.text.trim().toLowerCase();
        if (query.isNotEmpty) {
          final fileName = getFileNameFromPath(fullPath).toLowerCase();
          if (fileName.contains(query)) {
            _filteredDocumentPaths.add(fullPath);
          }
        }
      }
    });

    _previewFutures.putIfAbsent(fullPath, () => _loadPreviewFuture(fullPath));

    // Регистрируем и загружаем на сервер
    () async {
      final entryName = () {
        final fileName = fullPath.split('/').last;
        final dot = fileName.lastIndexOf('.');
        return dot != -1 ? fileName.substring(0, dot) : fileName;
      }();
      await DocumentRegistry().add(DocEntry(
        localPath: fullPath,
        remoteId: null,
        name: entryName,
      ));
      try {
        final remote = await DocumentSyncService()
            .upload(File(fullPath), name: entryName);
        await DocumentRegistry().updateRemoteId(fullPath, remote.id);
      } catch (e) {
        debugPrint('Import upload failed: $e');
      }
    }();
  }

  void _importDocument(FileType fileType) async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: fileType,
      allowMultiple: false,
    );

    if (result != null && result.files.first.path != null) {
      final fullPath = result.files.first.path!;
      final fileName = getFileNameFromPath(fullPath);

      _addDocument(fullPath);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Документ "$fileName" импортирован.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Импортировать документ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.green),
              title: const Text('Выбрать фото'),
              onTap: () {
                Navigator.pop(context);
                _importDocument(FileType.image);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.blue),
              title: const Text('Выбрать файл '),
              onTap: () {
                Navigator.pop(context);
                _importDocument(FileType.any);
              },
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Future<bool> _requestPermissions() async {
    final messenger = ScaffoldMessenger.of(context);
    final storageStatus = await Permission.storage.request();
    final photosStatus = await Permission.photos.request();

    if (storageStatus.isGranted || photosStatus.isGranted) {
      return true;
    } else
    if (storageStatus.isPermanentlyDenied || photosStatus.isPermanentlyDenied) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
                'Разрешение на хранение отклонено. Откройте настройки приложения.'),
            action: SnackBarAction(
                label: 'Настройки', onPressed: openAppSettings),
          ),
        );
      }
    }
    return false;
  }

  void _navigateToDocumentView(String fullPath) async {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final fileName = getFileNameFromPath(fullPath);
    final lowerCaseFileName = fileName.toLowerCase();

    if (lowerCaseFileName.endsWith('.jpg') ||
        lowerCaseFileName.endsWith('.png') ||
        lowerCaseFileName.endsWith('.jpeg')) {
      await OpenFilex.open(fullPath);
    } else if (lowerCaseFileName.endsWith('.pdf')) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) =>
              PdfViewerScreen(filePath: fullPath, fileName: fileName),
        ),
      );
    } else if (lowerCaseFileName.endsWith('.docx') ||
        lowerCaseFileName.endsWith('.doc')) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) =>
              DocxViewerScreen(filePath: fullPath, fileName: fileName),
        ),
      );
    } else if (lowerCaseFileName.endsWith('.txt')) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) =>
              TextFileViewerScreen(filePath: fullPath, fileName: fileName),
        ),
      );
    } else {
      try {
        final file = File(fullPath);
        if (await file.exists()) {
          final result = await OpenFilex.open(fullPath);

          if (result.type != ResultType.done && mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                    'Не удалось открыть файл. Убедитесь, что у вас установлено приложение для формата ${fileName
                        .split('.')
                        .last
                        .toUpperCase()}.'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('Файл не найден: $fileName'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Ошибка открытия файла: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 70,
        title: const Text(
          'Мои файлы',
          style: TextStyle(
              color: Colors.black, fontWeight: FontWeight.w500, fontSize: 24),
        ),
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(245, 245, 245, 1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Поиск по названию файла',
                        hintStyle: const TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _clearSearch,
                        )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_isSearching && _filteredDocumentPaths.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Ничего не найдено по запросу "${_searchController.text}"',
                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              )
            else
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Найдено: ${_filteredDocumentPaths.length} файлов',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),

            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else
              if (_displayedDocumentPaths.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.document_scanner,
                          size: 100,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 20),

                        if (_isSearching) ...[
                          const Text(
                            textAlign: TextAlign.center,
                            'Попробуйте изменить запрос поиска',
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        ] else
                          ...[
                            const Text(
                              textAlign: TextAlign.center,
                              'Сюда будут добавлены все файлы после операций из вкладки "Действия"',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _displayedDocumentPaths.length,
                    itemBuilder: (context, index) {
                      final filePath = _displayedDocumentPaths[index];
                      final fileName = getFileNameFromPath(filePath);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        child: ListTile(
                          leading: _buildFilePreview(filePath),
                          title: Text(fileName),
                          trailing: Builder(
                            builder: (innerContext) {
                              return IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed: () =>
                                    _showDocumentMenu(innerContext, index),
                              );
                            },
                          ),
                          onTap: () {
                            _navigateToDocumentView(filePath);
                          },
                        ),
                      );
                    },
                  ),
                ),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: OutlinedButton.icon(
                onPressed: () => _showImportOptions(context),
                icon: const Icon(Icons.folder_open, color: Colors.black),
                label: const Text('Импорт',
                    style: TextStyle(fontSize: 16, color: Colors.black)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
