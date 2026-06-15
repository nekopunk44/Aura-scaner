import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/server_config.dart';
import '../../../services/api_service.dart';
import '../../../services/document_sync_service.dart';
import '../../../l10n/app_localizations.dart';

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
  String? _busyLabel;
  String? _error;

  void _setBusy(String? label) {
    if (!mounted) return;
    setState(() {
      _isBusy = label != null;
      _busyLabel = label;
    });
  }
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
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'doc', 'txt', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.first.path == null) return;

    final file = File(result.files.first.path!);
    _setBusy(l10n.remoteUploadBusy);
    try {
      await _apiService.syncBaseUrl();
      await _syncService.upload(file);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteUploaded(p.basename(file.path)))),
      );
      await _loadRemoteDocuments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteUploadError(e.toString()))),
      );
    } finally {
      _setBusy(null);
    }
  }

  Future<void> _downloadDocument(RemoteDocument doc) async {
    final l10n = AppLocalizations.of(context);
    _setBusy(l10n.remoteDownloadBusy);
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
        SnackBar(content: Text(l10n.remoteDownloaded(fileName))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteDownloadError(e.toString()))),
      );
    } finally {
      _setBusy(null);
    }
  }

  String _buildUniqueLocalName(String originalName) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(originalName);
    final base = p.basenameWithoutExtension(originalName);
    return ext.isEmpty ? '${base}_$stamp' : '${base}_$stamp$ext';
  }

  Future<void> _renameRemoteDocument(RemoteDocument doc) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: doc.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isDarkDialog = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkDialog ? const Color(0xFF1E2A3A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.remoteRenameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.remoteNewName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(l10n.actionSave,
                  style: const TextStyle(color: Color(0xFF2CA5E0))),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty || newName == doc.name) return;

    _setBusy(l10n.remoteRenameBusy);
    try {
      await _apiService.syncBaseUrl();
      await _syncService.rename(doc.id, newName);
      if (!mounted) return;
      await _loadRemoteDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteRenamed)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteRenameError(e.toString()))),
      );
    } finally {
      _setBusy(null);
    }
  }

  Future<void> _deleteRemoteDocument(RemoteDocument doc) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDarkDialog = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkDialog ? const Color(0xFF1E2A3A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.remoteDeleteTitle),
          content: Text(l10n.remoteDeleteConfirm(doc.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.actionCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: Text(l10n.actionDelete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    _setBusy(l10n.remoteDeleteBusy);
    try {
      await _apiService.syncBaseUrl();
      await _syncService.delete(doc.id);
      if (!mounted) return;
      await _loadRemoteDocuments();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.remoteDeleteError(e.toString()))),
      );
    } finally {
      _setBusy(null);
    }
  }

  Future<void> _editServerUrl() async {
    await ServerConfig().load();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: ServerConfig().baseUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isDarkDialog = Theme.of(dialogContext).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkDialog ? const Color(0xFF1E2A3A) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.dialogRename),
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
              child: Text(l10n.actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(l10n.actionSave,
                  style: const TextStyle(color: Color(0xFF2CA5E0))),
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
        SnackBar(content: Text(l10n.remoteServerSaveError(e.toString()))),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remoteDocTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: l10n.dialogRename,
            onPressed: _isBusy ? null : _editServerUrl,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.remoteRefresh,
            onPressed: _isBusy ? null : _loadRemoteDocuments,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _pickAndUpload,
        icon: const Icon(Icons.cloud_upload),
        label: Text(l10n.remoteUpload),
      ),
      body: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
          return Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF2CA5E0).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2CA5E0).withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud, color: Color(0xFF2CA5E0)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.remoteServerLabel(_serverUrl),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0))),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, size: 64, color: subColor),
                      const SizedBox(height: 16),
                      Text(
                        l10n.remoteLoadError(_error!),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: subColor),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRemoteDocuments,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2CA5E0),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l10n.actionRetry),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_documents.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_queue, size: 72, color: subColor),
                      const SizedBox(height: 16),
                      Text(
                        l10n.remoteEmpty,
                        style: TextStyle(fontSize: 16, color: subColor),
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
                          leading: Icon(_iconForFormat(doc.format), color: const Color(0xFF2CA5E0)),
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
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'download',
                                child: Text(l10n.remoteDownloadLocal),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Text(l10n.dialogRename),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.actionDelete),
                              ),
                            ],
                          ),
                          onTap: _isBusy ? null : () => _downloadDocument(doc),
                        ),
                      );
                    },
                  ),
                  if (_isBusy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: Color(0xFF2CA5E0)),
                              if (_busyLabel != null) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _busyLabel!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
        },
      ),
    );
  }
}
