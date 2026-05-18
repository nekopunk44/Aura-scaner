import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/server_config.dart';
import '../../../services/api_service.dart';
import '../../../services/document_sync_service.dart';

const _documentKey = 'saved_document_paths';

class RemoteDocumentsScreen extends StatefulWidget {
  final VoidCallback? onLocalDocumentImported;

  const RemoteDocumentsScreen({super.key, this.onLocalDocumentImported});

  @override
  State<RemoteDocumentsScreen> createState() => _RemoteDocumentsScreenState();
}

class _RemoteDocumentsScreenState extends State<RemoteDocumentsScreen> {
  final _syncService = DocumentSyncService();
  final _apiService = ApiService();

  List<RemoteDocument> _documents = [];
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;
  String _serverUrl = ServerConfig().baseUrl;

  @override
  void initState() {
    super.initState();
    _loadRemoteDocuments();
  }

  Future<void> _loadRemoteDocuments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _apiService.syncBaseUrl();
      await ServerConfig().load();
      final docs = await _syncService.list();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _serverUrl = ServerConfig().baseUrl;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _serverUrl = ServerConfig().baseUrl;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'doc', 'txt', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.first.path == null) return;

    final file = File(result.files.first.path!);
    setState(() => _isBusy = true);
    try {
      await _apiService.syncBaseUrl();
      await _syncService.upload(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Загружено в облако: ${p.basename(file.path)}')),
      );
      await _loadRemoteDocuments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _downloadDocument(RemoteDocument doc) async {
    setState(() => _isBusy = true);
    try {
      await _apiService.syncBaseUrl();
      final dir = await getApplicationDocumentsDirectory();
      final fileName = _buildUniqueLocalName(doc.name);
      final savePath = '${dir.path}/$fileName';

      await _syncService.download(doc.id, savePath);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(savePath)) {
        paths.add(savePath);
        await prefs.setStringList(_documentKey, paths);
      }

      if (!mounted) return;
      widget.onLocalDocumentImported?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Скачано: $fileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка скачивания: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  String _buildUniqueLocalName(String originalName) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(originalName);
    final base = p.basenameWithoutExtension(originalName);
    return ext.isEmpty ? '${base}_$stamp' : '${base}_$stamp$ext';
  }

  Future<void> _renameRemoteDocument(RemoteDocument doc) async {
    final controller = TextEditingController(text: doc.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Переименовать в облаке'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Новое имя документа',
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

    if (newName == null || newName.isEmpty || newName == doc.name) return;

    setState(() => _isBusy = true);
    try {
      await _apiService.syncBaseUrl();
      await _syncService.rename(doc.id, newName);
      if (!mounted) return;
      await _loadRemoteDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Имя облачного документа обновлено')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка переименования: $e')),
      );
      setState(() => _isBusy = false);
    }
  }

  Future<void> _deleteRemoteDocument(RemoteDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить из облака'),
          content: Text('Удалить "${doc.name}" с сервера?'),
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
      await _apiService.syncBaseUrl();
      await _syncService.delete(doc.id);
      if (!mounted) return;
      await _loadRemoteDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Документ удалён из облака')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $e')),
      );
      setState(() => _isBusy = false);
    }
  }

  Future<void> _editServerUrl() async {
    await ServerConfig().load();
    if (!mounted) return;
    final controller = TextEditingController(text: ServerConfig().baseUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Адрес сервера'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'http://localhost:3000/api',
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

    if (newUrl == null || newUrl.isEmpty) return;

    try {
      await ServerConfig().save(newUrl);
      if (!mounted) return;
      await _apiService.syncBaseUrl();
      if (!mounted) return;
      setState(() => _serverUrl = ServerConfig().baseUrl);
      await _loadRemoteDocuments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения адреса: $e')),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _iconForFormat(String format) {
    final value = format.toLowerCase();
    if (value.contains('pdf')) return Icons.picture_as_pdf;
    if (value.contains('doc')) return Icons.description;
    if (value.contains('txt')) return Icons.text_snippet;
    if (value.contains('jpg') || value.contains('jpeg') || value.contains('png')) {
      return Icons.image;
    }
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Облачные документы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Адрес сервера',
            onPressed: _isBusy ? null : _editServerUrl,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _isBusy ? null : _loadRemoteDocuments,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _pickAndUpload,
        icon: const Icon(Icons.cloud_upload),
        label: const Text('Загрузить'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Сервер: $_serverUrl',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Не удалось загрузить облачные документы.\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRemoteDocuments,
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_documents.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_queue, size: 72, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'В облаке пока нет документов',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: _documents.length,
                    itemBuilder: (context, index) {
                      final doc = _documents[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Icon(_iconForFormat(doc.format), color: Colors.blue),
                          title: Text(
                            doc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${doc.format.toUpperCase()} • ${_formatFileSize(doc.fileSize)}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'download':
                                  _downloadDocument(doc);
                                  break;
                                case 'rename':
                                  _renameRemoteDocument(doc);
                                  break;
                                case 'delete':
                                  _deleteRemoteDocument(doc);
                                  break;
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'download',
                                child: Text('Скачать в локальные'),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Переименовать'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Удалить'),
                              ),
                            ],
                          ),
                          onTap: _isBusy ? null : () => _downloadDocument(doc),
                        ),
                      );
                    },
                  ),
                  if (_isBusy)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x22000000),
                        child: Center(child: CircularProgressIndicator()),
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
