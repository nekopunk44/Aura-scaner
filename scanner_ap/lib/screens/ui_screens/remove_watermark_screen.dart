import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../services/ai_service.dart';
import '../../services/document_registry.dart';
import '../../widgets/before_after_slider.dart';

const _documentKey = 'saved_document_paths';

/// Удаление водяного знака. Поведение как у восстановления фото: при открытии
/// сразу запускается обработка (FLUX Kontext на весь кадр), показывается экран
/// загрузки с туманом и прогрессом, затем сравнение «до/после». Ручного
/// выделения / детекта / смены изображения больше нет — только «Сохранить».
class RemoveWatermarkScreen extends StatefulWidget {
  const RemoveWatermarkScreen({
    super.key,
    this.onSaved,
    this.initialImagePath,
    this.autoDetectOnOpen = false,
  });

  final VoidCallback? onSaved;
  final String? initialImagePath;
  // Оставлен для совместимости вызова; обработка теперь стартует автоматически.
  final bool autoDetectOnOpen;

  @override
  State<RemoveWatermarkScreen> createState() => _RemoveWatermarkScreenState();
}

class _RemoveWatermarkScreenState extends State<RemoveWatermarkScreen> {
  File? _selectedFile; // оригинал (до)
  File? _previewFile; // результат (после)

  bool _isProcessing = false;
  bool _isSaving = false;
  double _progress = 0.0;
  Timer? _progressTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialImage();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  bool get _resultReady =>
      _selectedFile != null &&
      _previewFile != null &&
      _previewFile!.path != _selectedFile!.path;

  Future<void> _loadInitialImage() async {
    final initialPath = widget.initialImagePath;
    if (initialPath == null || initialPath.isEmpty) return;
    final file = File(initialPath);
    if (!await file.exists()) return;
    _setSourceAndProcess(file);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      _setSourceAndProcess(File(picked.path));
    }
  }

  /// Задаёт исходное фото и сразу запускает удаление знака.
  void _setSourceAndProcess(File file) {
    setState(() {
      _selectedFile = file;
      _previewFile = file;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _process();
    });
  }

  void _startProgress() {
    _progress = 0.0;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _progress += (0.95 - _progress) * 0.012);
    });
  }

  /// Удаление водяного знака со всего кадра (FLUX Kontext). При сбое —
  /// экран ошибки с кнопкой «Повторить».
  Future<void> _process() async {
    if (_selectedFile == null || _isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.0;
    });
    _startProgress();
    try {
      final bytes = await _selectedFile!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      final jpeg = decoded != null
          ? Uint8List.fromList(img.encodeJpg(decoded, quality: 95))
          : Uint8List.fromList(bytes);
      final resultBytes = await AIService().dewatermark(jpeg);

      final dir = await getTemporaryDirectory();
      final out =
          '${dir.path}/dewm_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(out);
      await file.writeAsBytes(resultBytes);
      if (mounted) setState(() => _previewFile = file);
    } on AiException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorMessage = switch (e.kind) {
            AiErrorKind.timeout => l10n.wmAiErrorTimeout,
            AiErrorKind.unavailable => l10n.wmAiErrorUnavailable,
            AiErrorKind.generic => l10n.wmAiErrorGeneric,
          };
        });
      }
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _progress = 1.0);
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _save() async {
    if (_previewFile == null || _isProcessing || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'nowm_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = '${dir.path}/$name';
      await _previewFile!.copy(dest);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(dest)) {
        paths.add(dest);
        await prefs.setStringList(_documentKey, paths);
      }
      await DocumentRegistry().load();
      await DocumentRegistry().add(
        DocEntry(
          localPath: dest,
          remoteId: null,
          name: DocumentRegistry.nameFromPath(dest),
        ),
      );

      widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).savedPlain),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openZoom() {
    if (_previewFile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ZoomView(file: _previewFile!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.wmTitle),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          if (_resultReady && !_isProcessing && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: l10n.restoreZoom,
              onPressed: _openZoom,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _previewFile != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox.expand(child: _buildPhotoContent(l10n)),
                    ),
                  )
                : Center(
                    child: GestureDetector(
                      onTap: _isProcessing ? null : _pickImage,
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                const Color(0xFF2CA5E0).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_photo_alternate_outlined,
                                size: 52, color: Color(0xFF2CA5E0)),
                            const SizedBox(height: 12),
                            Text(l10n.importChoosePhoto,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor)),
                            const SizedBox(height: 4),
                            Text('JPG, PNG',
                                style: TextStyle(fontSize: 13, color: subColor)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (_previewFile != null && _errorMessage == null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_isProcessing || _isSaving) ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2CA5E0),
                      disabledBackgroundColor:
                          const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(l10n.actionSave,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoContent(AppLocalizations l10n) {
    if (_isProcessing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_previewFile!, fit: BoxFit.contain),
          Positioned.fill(
            child: ProcessingOverlay(
              progress: _progress,
              label: l10n.wmRemoving,
              icon: Icons.auto_fix_high,
            ),
          ),
        ],
      );
    }
    if (_errorMessage != null) {
      return _buildErrorOverlay(l10n);
    }
    if (_resultReady) {
      return BeforeAfterSlider(
        before: _selectedFile!,
        after: _previewFile!,
        beforeLabel: l10n.restoreBefore,
        afterLabel: l10n.restoreAfter,
      );
    }
    return Image.file(_previewFile!, fit: BoxFit.contain);
  }

  Widget _buildErrorOverlay(AppLocalizations l10n) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(_previewFile!, fit: BoxFit.contain),
        Container(color: Colors.black.withValues(alpha: 0.6)),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 44),
                const SizedBox(height: 14),
                Text(
                  l10n.wmFailedTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 200,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _process,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.restoreRetry),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2CA5E0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
