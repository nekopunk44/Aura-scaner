import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../services/ai_service.dart';
import '../../services/document_registry.dart';
import '../../widgets/before_after_slider.dart';

const _documentKey = 'saved_document_paths';

class RestorePhotoScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  final String? initialImagePath;
  // Оставлен для совместимости с вызовами; восстановление теперь запускается
  // автоматически при загрузке фото в любом случае.
  final bool autoEnhanceOnOpen;

  const RestorePhotoScreen({
    super.key,
    this.onSaved,
    this.initialImagePath,
    this.autoEnhanceOnOpen = false,
  });

  @override
  State<RestorePhotoScreen> createState() => _RestorePhotoScreenState();
}

class _RestorePhotoScreenState extends State<RestorePhotoScreen> {
  File? _selectedFile;
  File? _previewFile;

  bool _isProcessing = false; // идёт ИИ-восстановление (показываем «туман»)
  bool _isSaving = false;
  double _progress = 0.0; // 0..1 — оценочный прогресс обработки
  Timer? _progressTimer;

  double _strength = 0.25; // 0 = Естественно, 1 = Чётче
  String? _errorMessage; // текст ошибки последнего восстановления (если было)

  // Сила → fidelity CodeFormer: Естественно (0) = 0.95 … Чётче (1) = 0.50.
  double get _fidelity => 0.95 - _strength * 0.45;

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

  Future<void> _loadInitialImage() async {
    final initialPath = widget.initialImagePath;
    if (initialPath == null || initialPath.isEmpty) return;

    final file = File(initialPath);
    if (!await file.exists()) return;

    _setSourceAndRestore(file);
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      _setSourceAndRestore(File(picked.path));
    }
  }

  /// Задаёт исходное фото и сразу запускает ИИ-восстановление — ручного
  /// редактирования больше нет, обработка стартует автоматически.
  void _setSourceAndRestore(File file) {
    setState(() {
      _selectedFile = file;
      _previewFile = file;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _aiRestore();
    });
  }

  /// Оценочный прогресс: реального процента от Replicate нет, поэтому плавно
  /// приближаемся к ~95%, замедляясь; до 100% доводим в момент готовности.
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

  /// Локальное улучшение — фолбэк, если облачное восстановление недоступно.
  Future<void> _localEnhanceCore() async {
    if (_selectedFile == null) return;
    final bytes = await _selectedFile!.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return;

    final sharpened = img.convolution(
      image,
      filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
      offset: 0,
    );
    final enhanced = img.adjustColor(
      sharpened,
      contrast: 1.1,
      brightness: 1.05,
      saturation: 1.1,
    );

    final dir = await getApplicationDocumentsDirectory();
    final name = 'restored_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '${dir.path}/$name';
    await File(path)
        .writeAsBytes(Uint8List.fromList(img.encodeJpg(enhanced, quality: 92)));

    if (mounted) setState(() => _previewFile = File(path));
  }

  /// Облачное восстановление (Replicate, две стадии) с выбранной силой.
  /// При сбое показываем экран ошибки с кнопкой «Повторить» (не молчаливый
  /// фолбэк) — пользователь сам решает: повторить или базовое улучшение.
  Future<void> _aiRestore() async {
    if (_selectedFile == null || _isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.0;
    });
    _startProgress();
    try {
      final restored =
          await AIService().restorePhoto(_selectedFile!, fidelity: _fidelity);
      if (mounted) setState(() => _previewFile = restored);
    } on AiException catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorMessage = switch (e.kind) {
            AiErrorKind.timeout => l10n.aiErrorTimeout,
            AiErrorKind.unavailable => l10n.aiErrorUnavailable,
            AiErrorKind.generic => l10n.aiErrorGeneric,
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

  /// «Базовое улучшение» с экрана ошибки — локальный фолбэк без сети.
  Future<void> _applyLocalEnhance() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _progress = 0.0;
    });
    _startProgress();
    try {
      await _localEnhanceCore();
    } finally {
      _progressTimer?.cancel();
      if (mounted) {
        setState(() => _progress = 1.0);
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted) setState(() => _isProcessing = false);
      }
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

  Future<void> _save() async {
    if (_previewFile == null || _isProcessing || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'restored_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

  /// Есть ли отдельный результат восстановления (путь отличается от
  /// оригинала) — тогда показываем сравнение «до/после».
  bool get _resultReady =>
      _selectedFile != null &&
      _previewFile != null &&
      _previewFile!.path != _selectedFile!.path;

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
        title: Text(l10n.featRestorePhoto),
        centerTitle: true,
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
                            color: const Color(0xFF2CA5E0).withValues(alpha: 0.3),
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
          _buildBottomBar(l10n),
        ],
      ),
    );
  }

  /// Контент области фото: туман при обработке, экран ошибки, сравнение
  /// «до/после» по готовности, либо просто фото.
  Widget _buildPhotoContent(AppLocalizations l10n) {
    if (_isProcessing) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_previewFile!, fit: BoxFit.contain),
          Positioned.fill(
            child: ProcessingOverlay(
              progress: _progress,
              label: l10n.restoreProcessing,
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

  /// Экран ошибки восстановления: затемнённое фото + «Повторить» / «Базовое
  /// улучшение» (вместо мелкого тоста).
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
                  l10n.restoreFailedTitle,
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
                    onPressed: _aiRestore,
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
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _applyLocalEnhance,
                  child: Text(l10n.restoreUseBasic,
                      style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Нижняя панель: по готовности — ползунок силы + «Обработать заново» +
  /// «Сохранить». На экране ошибки прячется (кнопки в оверлее).
  Widget _buildBottomBar(AppLocalizations l10n) {
    if (_previewFile == null || _errorMessage != null) {
      return const SizedBox.shrink();
    }
    final bool ready = _resultReady && !_isProcessing;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ready) ...[
              _buildStrengthRow(l10n),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                if (ready) ...[
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _aiRestore,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(l10n.restoreReprocess),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2CA5E0),
                          side: const BorderSide(color: Color(0xFF2CA5E0)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(child: _buildSaveButton(l10n)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthRow(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : const Color(0xFF6B7A99);
    final labelStyle = TextStyle(fontSize: 12, color: labelColor);
    return Row(
      children: [
        Text(l10n.restoreNatural, style: labelStyle),
        Expanded(
          child: Slider(
            value: _strength,
            onChanged:
                _isProcessing ? null : (v) => setState(() => _strength = v),
            activeColor: const Color(0xFF2CA5E0),
          ),
        ),
        Text(l10n.restoreSharper, style: labelStyle),
      ],
    );
  }

  Widget _buildSaveButton(AppLocalizations l10n) {
    return SizedBox(
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
    );
  }
}
