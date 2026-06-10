// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:collection';
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
import '../../../utils/app_notification.dart';
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

  static const int _kMaxPreviewFutures = 80;
  final LinkedHashMap<String, Future<Uint8List?>> _previewFutures =
      LinkedHashMap<String, Future<Uint8List?>>();

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _previewFutures.clear();
    super.dispose();
  }

  Future<Uint8List?> _previewFutureFor(String filePath) {
    final existing = _previewFutures.remove(filePath);
    if (existing != null) {
      _previewFutures[filePath] = existing;
      return existing;
    }
    final future = _loadPreviewFuture(filePath);
    _previewFutures[filePath] = future;
    while (_previewFutures.length > _kMaxPreviewFutures) {
      _previewFutures.remove(_previewFutures.keys.first);
    }
    return future;
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), _applySearchFilter);
  }

  void _applySearchFilter() {
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _filteredDocumentPaths.clear();
      });
    } else {
      setState(() {
        _isSearching = true;
        _filteredDocumentPaths
          ..clear()
          ..addAll(_documentPaths.where((path) =>
              getFileNameFromPath(path).toLowerCase().contains(query)));
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

  List<String> get _displayedDocumentPaths =>
      _isSearching ? _filteredDocumentPaths : _documentPaths;

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    final registry = DocumentRegistry();
    await registry.load();

    // Используем асинхронную проверку чтобы не блокировать UI поток
    final checks = await Future.wait(
      registry.entries.map((e) async {
        final exists = await File(e.localPath).exists();
        return exists ? e : null;
      }),
    );
    final localEntries = checks.whereType<DocEntry>().toList();

    if (mounted) {
      setState(() {
        _documentPaths
          ..clear()
          ..addAll(localEntries.map((e) => e.localPath));
        _isLoading = false;
      });
    }

    _syncWithCloud(registry);
  }

  Future<void> _syncWithCloud(DocumentRegistry registry) async {
    try {
      final remoteList = await DocumentSyncService().list();
      final localRemoteIds = registry.entries
          .map((e) => e.remoteId)
          .whereType<String>()
          .toSet();

      for (final remote in remoteList) {
        if (!localRemoteIds.contains(remote.id)) {
          await _downloadAndRegister(remote, registry);
        }
      }

      final unsynced = registry.entries
          .where((e) => e.remoteId == null)
          .toList();
      for (final entry in unsynced) {
        if (await File(entry.localPath).exists()) {
          await _retryUpload(entry);
        }
      }

      await registry.load();
      final checks = await Future.wait(
        registry.entries.map((e) async {
          final exists = await File(e.localPath).exists();
          return exists ? e : null;
        }),
      );
      final updatedEntries = checks.whereType<DocEntry>().toList();

      if (!mounted) return;
      setState(() {
        _documentPaths
          ..clear()
          ..addAll(updatedEntries.map((e) => e.localPath));
      });
    } catch (e) {
      debugPrint('Cloud sync error: $e');
    }
  }

  Future<void> _downloadAndRegister(
      RemoteDocument remote, DocumentRegistry registry) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      var finalPath = '${dir.path}/${remote.name}.${remote.format}';
      var counter = 1;
      while (await File(finalPath).exists()) {
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

  Future<void> _retryUpload(DocEntry entry) async {
    try {
      final remote = await DocumentSyncService()
          .upload(File(entry.localPath), name: entry.name);
      await DocumentRegistry().updateRemoteId(entry.localPath, remote.id);
    } catch (e) {
      debugPrint('Retry upload failed: $e');
    }
  }

  Future<Uint8List?> _loadPreviewFuture(String filePath) async {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    try {
      if (fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.png') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.bmp')) {
        return await File(filePath).readAsBytes();
      } else if (fileName.endsWith('.pdf')) {
        return await generatePdfPreview(filePath);
      } else if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
        return await generateDocxPreview(filePath);
      }
      // Любой текстовый формат (txt, md, csv, json, log, yaml, xml...)
      // рисуем как text-preview — пользователь сразу видит первые строки
      // вместо безликой иконки.
      try {
        final content = await File(filePath).readAsString();
        return await _createTextPreview(content);
      } catch (_) {
        return null;
      }
    } catch (e) {
      debugPrint('Preview error for $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _createTextPreview(String content) async {
    try {
      // Берём первые ~12 не пустых строк — это даёт несколько заметных
      // строк текста в превью, а не 100 склеенных символов в одну линию.
      final lines = content
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(12)
          .toList();
      final preview = lines.join('\n');
      return await _textToImage(preview);
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> _textToImage(String text) async {
    const double w = 220;
    const double h = 220;
    const double pad = 14;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, w, h));
    // Светлая страница с тёмным текстом — выглядит как настоящий
    // документ, а не «тёмная плашка с цифрами».
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFAFCFF),
    );
    // Лента-акцент сверху — чтобы превью читалось как «документ».
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, w, 6),
      Paint()..color = const Color(0xFF2CA5E0),
    );
    final paragraphBuilder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 10,
        textDirection: TextDirection.ltr,
        maxLines: 14,
        ellipsis: '…',
      ),
    )
      ..pushStyle(ui.TextStyle(
        color: const Color(0xFF1A1A2E),
        fontSize: 10,
        height: 1.35,
      ))
      ..addText(text);
    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: w - pad * 2));
    canvas.drawParagraph(paragraph, const Offset(pad, pad + 6));
    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Widget _buildFilePreview(String filePath, bool isDark, {double size = 52}) {
    final fileName = getFileNameFromPath(filePath).toLowerCase();
    final future = _previewFutureFor(filePath);

    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _previewShimmer(isDark, size: size);
        }

        final previewBytes = snapshot.data;
        if (previewBytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: size,
              height: size,
              child: Image.memory(
                previewBytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFileIcon(fileName, isDark, size: size),
              ),
            ),
          );
        }

        return _buildFileIcon(fileName, isDark, size: size);
      },
    );
  }

  Widget _previewShimmer(bool isDark, {double size = 52}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: isDark ? Colors.white24 : const Color(0xFFCCD3E0),
          ),
        ),
      ),
    );
  }

  Widget _buildFileIcon(String fileName, bool isDark, {double size = 52}) {
    final (color, icon) = _fileStyle(fileName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.35 : 0.25), width: 1),
      ),
      child: Center(child: Icon(icon, color: color, size: size * 0.42)),
    );
  }

  (Color, IconData) _fileStyle(String fileName) {
    if (fileName.endsWith('.pdf')) {
      return (const Color(0xFFEF5350), Icons.picture_as_pdf_outlined);
    }
    if (fileName.endsWith('.docx') || fileName.endsWith('.doc')) {
      return (const Color(0xFF2CA5E0), Icons.description_outlined);
    }
    if (fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png')) {
      return (const Color(0xFF26C060), Icons.image_outlined);
    }
    if (fileName.endsWith('.txt')) {
      return (const Color(0xFF9E9E9E), Icons.text_fields_rounded);
    }
    return (const Color(0xFFFF9800), Icons.insert_drive_file_outlined);
  }

  void _exportDocument(String fullPath) async {
    if (!mounted) return;

    if (!(await _requestPermissions())) return;

    final fileToExport = File(fullPath);
    final fileName = getFileNameFromPath(fullPath);
    final lower = fileName.toLowerCase();

    try {
      if (!await fileToExport.exists()) {
        throw Exception('Файл не найден: $fullPath');
      }

      if (lower.endsWith('.jpg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.jpeg')) {
        final bytes = await fileToExport.readAsBytes();
        final result =
            await ImageGallerySaverPlus.saveImage(bytes, name: fileName);
        final ok = result is Map
            ? result['isSuccess'] == true || result['isSuccess'] == 1
            : result == true;
        if (!ok) throw Exception('Не удалось сохранить в Галерею.');
        if (mounted) {
          AppNotification.show(context,
              message: 'Сохранено в Галерею', type: NotificationType.success);
        }
      } else {
        final bytes = await fileToExport.readAsBytes();
        final newPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          bytes: bytes,
        );
        if (newPath == null) throw Exception('Сохранение отменено.');
        if (mounted) {
          AppNotification.show(context,
              message: 'Файл сохранён', type: NotificationType.success);
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.show(context,
            message: e.toString().replaceFirst('Exception: ', ''));
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

    // fire-and-forget: удаление локального файла + удаление из реестра/облака.
    // Не блокируем UI; список уже обновлён через setState() выше.
    () async {
      try {
        await File(filePath).delete();
      } catch (e) {
        debugPrint('Delete error: $e');
      }

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
      AppNotification.show(context,
          message: '"$fileName" удалён', type: NotificationType.info);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final dialogBg =
            isDark ? const Color(0xFF1a2535) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
        final subtextColor =
            isDark ? Colors.white54 : const Color(0xFF8A94A6);
        return Dialog(
          backgroundColor: dialogBg,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Переименовать',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : const Color(0xFFF2F6FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF2CA5E0), width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                if (fileExtension != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Расширение: $fileExtension',
                    style: TextStyle(color: subtextColor, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        style: TextButton.styleFrom(
                          foregroundColor: subtextColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final nav = Navigator.of(dialogCtx);
                          String newBaseName = controller.text.trim();
                          if (newBaseName.isEmpty) {
                            AppNotification.show(context,
                                message: 'Имя не может быть пустым');
                            return;
                          }

                          if (fileExtension != null &&
                              newBaseName
                                  .toLowerCase()
                                  .endsWith(fileExtension.toLowerCase())) {
                            newBaseName = newBaseName.substring(
                                0, newBaseName.length - fileExtension.length);
                          }

                          final newFullName =
                              newBaseName + (fileExtension ?? '');
                          if (newFullName == currentFullName) {
                            nav.pop();
                            return;
                          }

                          final newPath =
                              currentPath.replaceAll(currentFullName, newFullName);

                          try {
                            if (await File(newPath).exists()) {
                              AppNotification.show(context,
                                  message: '"$newFullName" уже существует');
                              nav.pop();
                              return;
                            }

                            await File(currentPath).rename(newPath);
                            await DocumentRegistry()
                                .updateLocalPath(currentPath, newPath, newBaseName);

                            final remoteId =
                                DocumentRegistry().getRemoteId(newPath);
                            if (remoteId != null) {
                              try {
                                await DocumentSyncService()
                                    .rename(remoteId, newBaseName);
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
                              AppNotification.show(context,
                                  message: 'Переименовано в "$newFullName"',
                                  type: NotificationType.success);
                            }
                          } catch (e) {
                            if (mounted) {
                              AppNotification.show(context,
                                  message: 'Ошибка: ${e.toString()}');
                            }
                          }
                          nav.pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2CA5E0),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Готово',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDocumentMenu(BuildContext context, int index) {
    final fullPath = _isSearching
        ? _filteredDocumentPaths[index]
        : _documentPaths[index];
    final fileName = getFileNameFromPath(fullPath);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sheetBg = isDark ? const Color(0xFF152030) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white38 : const Color(0xFFAAB4C8);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEEF2F8);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: subtextColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: dividerColor, height: 1),
                _SheetAction(
                  icon: Icons.edit_outlined,
                  iconColor: const Color(0xFF2CA5E0),
                  iconBg: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                  label: 'Переименовать',
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _renameDocument(index);
                  },
                ),
                _SheetAction(
                  icon: Icons.save_alt_outlined,
                  iconColor: const Color(0xFF26C060),
                  iconBg: const Color(0xFF26C060).withValues(alpha: 0.12),
                  label: 'Сохранить / Экспорт',
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportDocument(fullPath);
                  },
                ),
                _SheetAction(
                  icon: Icons.share_outlined,
                  iconColor: const Color(0xFFFF9800),
                  iconBg: const Color(0xFFFF9800).withValues(alpha: 0.12),
                  label: 'Поделиться',
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareDocument(fullPath);
                  },
                ),
                Divider(color: dividerColor, height: 1),
                _SheetAction(
                  icon: Icons.delete_outline,
                  iconColor: const Color(0xFFEF5350),
                  iconBg: const Color(0xFFEF5350).withValues(alpha: 0.12),
                  label: 'Удалить',
                  textColor: const Color(0xFFEF5350),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1a2535) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF5350).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline,
                    color: Color(0xFFEF5350), size: 28),
              ),
              const SizedBox(height: 16),
              Text('Удалить файл?',
                  style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Файл будет удалён без возможности восстановления.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(
                        foregroundColor: subtextColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF5350),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Удалить',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) _deleteDocument(index);
  }

  Future<void> _shareDocument(String fullPath) async {
    final file = File(fullPath);
    if (!await file.exists()) {
      if (mounted) {
        AppNotification.show(context, message: 'Файл не найден');
      }
      return;
    }
    await Share.shareXFiles(
      [XFile(fullPath)],
      subject: getFileNameFromPath(fullPath),
    );
  }

  void _addDocument(String fullPath) {
    if (_documentPaths.contains(fullPath)) return;
    setState(() {
      _documentPaths.add(fullPath);
      if (_isSearching) {
        final query = _searchController.text.trim().toLowerCase();
        if (query.isNotEmpty &&
            getFileNameFromPath(fullPath).toLowerCase().contains(query)) {
          _filteredDocumentPaths.add(fullPath);
        }
      }
    });

    _previewFutures.putIfAbsent(
        fullPath, () => _loadPreviewFuture(fullPath));

    () async {
      final entryName = () {
        final name = fullPath.split('/').last;
        final dot = name.lastIndexOf('.');
        return dot != -1 ? name.substring(0, dot) : name;
      }();
      await DocumentRegistry()
          .add(DocEntry(localPath: fullPath, remoteId: null, name: entryName));
      try {
        final remote =
            await DocumentSyncService().upload(File(fullPath), name: entryName);
        await DocumentRegistry().updateRemoteId(fullPath, remote.id);
      } catch (e) {
        debugPrint('Import upload failed: $e');
      }
    }();
  }

  void _importDocument(FileType fileType) async {
    final result = await FilePicker.platform
        .pickFiles(type: fileType, allowMultiple: false);

    if (result != null && result.files.first.path != null) {
      final fullPath = result.files.first.path!;
      final fileName = getFileNameFromPath(fullPath);
      _addDocument(fullPath);
      if (mounted) {
        AppNotification.show(context,
            message: '"$fileName" импортирован',
            type: NotificationType.success);
      }
    }
  }

  void _showImportOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF152030) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor =
        isDark ? Colors.white38 : const Color(0xFFAAB4C8);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: subtextColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Импорт документа',
                    style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                _SheetAction(
                  icon: Icons.image_outlined,
                  iconColor: const Color(0xFF26C060),
                  iconBg: const Color(0xFF26C060).withValues(alpha: 0.12),
                  label: 'Выбрать фото',
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _importDocument(FileType.image);
                  },
                ),
                _SheetAction(
                  icon: Icons.folder_outlined,
                  iconColor: const Color(0xFF2CA5E0),
                  iconBg: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
                  label: 'Выбрать файл',
                  textColor: textColor,
                  onTap: () {
                    Navigator.pop(ctx);
                    _importDocument(FileType.any);
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

  Future<bool> _requestPermissions() async {
    final storageStatus = await Permission.storage.request();
    final photosStatus = await Permission.photos.request();

    if (storageStatus.isGranted || photosStatus.isGranted) return true;

    if (storageStatus.isPermanentlyDenied || photosStatus.isPermanentlyDenied) {
      if (mounted) {
        AppNotification.show(context,
            message: 'Разрешение отклонено. Откройте настройки.');
      }
    }
    return false;
  }

  void _navigateToDocumentView(String fullPath) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final fileName = getFileNameFromPath(fullPath);
    final lower = fileName.toLowerCase();

    if (lower.endsWith('.jpg') || lower.endsWith('.png') || lower.endsWith('.jpeg')) {
      await OpenFilex.open(fullPath);
    } else if (lower.endsWith('.pdf')) {
      navigator.push(MaterialPageRoute(
        builder: (_) => PdfViewerScreen(filePath: fullPath, fileName: fileName),
      ));
    } else if (lower.endsWith('.docx') || lower.endsWith('.doc')) {
      navigator.push(MaterialPageRoute(
        builder: (_) =>
            DocxViewerScreen(filePath: fullPath, fileName: fileName),
      ));
    } else if (lower.endsWith('.txt')) {
      navigator.push(MaterialPageRoute(
        builder: (_) =>
            TextFileViewerScreen(filePath: fullPath, fileName: fileName),
      ));
    } else {
      try {
        final file = File(fullPath);
        if (await file.exists()) {
          final result = await OpenFilex.open(fullPath);
          if (result.type != ResultType.done && mounted) {
            AppNotification.show(context,
                message:
                    'Не удалось открыть файл формата .${fileName.split('.').last.toUpperCase()}');
          }
        } else {
          if (mounted) {
            AppNotification.show(context, message: 'Файл не найден: $fileName');
          }
        }
      } catch (e) {
        if (mounted) {
          AppNotification.show(context,
              message: 'Ошибка открытия файла: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF0f1923) : const Color(0xFFF5F9FF);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subtextColor =
        isDark ? Colors.white38 : const Color(0xFFAAB4C8);
    final searchFill = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white;
    final searchBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE8EDF5);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEEF2F8);

    return Container(
      color: bgColor,
      child: Column(
        children: [
          // Search — на широком экране (landscape, tablet) ограничен
          // max-width 560 и центрирован, чтобы поле не растягивалось во
          // весь экран и казалось «балконом».
          Padding(
            padding:
                const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: searchFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: searchBorder, width: 1),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search_rounded,
                          color: subtextColor, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style:
                              TextStyle(color: textColor, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Поиск',
                            hintStyle: TextStyle(
                                color: subtextColor, fontSize: 14),
                            border: InputBorder.none,
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded,
                                        size: 18, color: subtextColor),
                                    onPressed: _clearSearch,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isSearching) ...[
                  const SizedBox(height: 10),
                  Text(
                    _filteredDocumentPaths.isEmpty
                        ? 'Ничего не найдено'
                        : 'Найдено: ${_filteredDocumentPaths.length}',
                    style: TextStyle(color: subtextColor, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
              ),
            ),
          ),

          // File list
          Expanded(
            child: _isLoading
                ? _buildSkeletonList(isDark)
                : _displayedDocumentPaths.isEmpty
                    ? _buildEmptyState(isDark, subtextColor)
                    : Builder(builder: (ctx) {
                      final isCompact = MediaQuery.of(ctx).size.width < 360;
                      final previewSize = isCompact ? 44.0 : 52.0;
                      final gap = isCompact ? 10.0 : 14.0;
                      final hPad = isCompact ? 10.0 : 14.0;
                      return ListView.builder(
                        padding: EdgeInsets.fromLTRB(isCompact ? 14 : 20, 0, isCompact ? 14 : 20, 120),
                        itemCount: _displayedDocumentPaths.length,
                        itemBuilder: (context, index) {
                          final filePath = _displayedDocumentPaths[index];
                          final fileName =
                              getFileNameFromPath(filePath);
                          final ext = fileName.contains('.')
                              ? fileName
                                  .split('.')
                                  .last
                                  .toUpperCase()
                              : '–';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    _navigateToDocumentView(filePath),
                                borderRadius:
                                    BorderRadius.circular(16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    border: Border.all(
                                        color: cardBorder, width: 1),
                                    boxShadow: isDark
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.04),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            )
                                          ],
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: hPad, vertical: 12),
                                  child: Row(
                                    children: [
                                      _buildFilePreview(
                                          filePath, isDark, size: previewSize),
                                      SizedBox(width: gap),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fileName,
                                              maxLines: isCompact ? 2 : 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: isCompact ? 13 : 14,
                                                fontWeight:
                                                    FontWeight.w500,
                                                height: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              ext,
                                              style: TextStyle(
                                                color: subtextColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                            Icons.more_vert_rounded,
                                            color: subtextColor,
                                            size: 20),
                                        onPressed: () =>
                                            _showDocumentMenu(
                                                context, index),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
          ),

        ],
      ),
    );
  }

  /// Вызывается из AppBar родителя (app_tabs_screen) когда тапнули по
  /// «+» — открывает тот же bottom-sheet выбора способа импорта.
  void showImportOptions() {
    if (!mounted) return;
    _showImportOptions(context);
  }

  Widget _buildSkeletonList(bool isDark) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFE8EDF5);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFF7F9FC);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _SkeletonRow(baseColor: baseColor, highlightColor: highlightColor),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color subtextColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Адаптивные размеры под landscape / низкие высоты —
        // на portrait иконка 96, на широком landscape 64.
        final isCompact = constraints.maxHeight < 360;
        final iconBox = isCompact ? 64.0 : 96.0;
        final iconSize = isCompact ? 30.0 : 44.0;
        final gap1 = isCompact ? 12.0 : 20.0;
        final gap2 = isCompact ? 4.0 : 8.0;
        final titleSize = isCompact ? 15.0 : 17.0;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 40, vertical: isCompact ? 12 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: iconBox,
                height: iconBox,
                decoration: BoxDecoration(
                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: iconSize,
                  color: const Color(0xFF2CA5E0),
                ),
              ),
              SizedBox(height: gap1),
              Text(
                _isSearching ? 'Ничего не найдено' : 'Файлов пока нет',
                style: TextStyle(
                  color: isDark ? Colors.white70 : const Color(0xFF1A1A2E),
                  fontSize: titleSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: gap2),
              Text(
                _isSearching
                    ? 'Попробуйте изменить запрос'
                    : 'Отсканируйте документ или импортируйте файл',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtextColor, fontSize: 13.5, height: 1.45),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color textColor;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label,
          style: TextStyle(
              color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  final Color baseColor;
  final Color highlightColor;
  const _SkeletonRow({required this.baseColor, required this.highlightColor});

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final color = Color.lerp(widget.baseColor, widget.highlightColor, (t < 0.5 ? t : 1 - t) * 2)!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: widget.highlightColor,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12, width: double.infinity,
                      decoration: BoxDecoration(
                        color: widget.highlightColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10, width: 120,
                      decoration: BoxDecoration(
                        color: widget.highlightColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
