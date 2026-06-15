import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import '../../services/ai_service.dart';
import '../../l10n/app_localizations.dart';

enum AiMode { analyze, eco }

class DocumentAiScreen extends StatefulWidget {
  final AiMode mode;
  final bool autoCamera;
  const DocumentAiScreen({super.key, required this.mode, this.autoCamera = false});

  static Widget analyze() => const DocumentAiScreen(mode: AiMode.analyze);
  static Widget camera() => const DocumentAiScreen(mode: AiMode.analyze, autoCamera: true);
  static Widget eco() => const DocumentAiScreen(mode: AiMode.eco);

  @override
  State<DocumentAiScreen> createState() => _DocumentAiScreenState();
}

class _DocumentAiScreenState extends State<DocumentAiScreen> {
  File? _imageFile;
  String? _result;
  AiErrorKind? _errorKind;
  bool _isLoading = false;

  bool get _isEco => widget.mode == AiMode.eco;

  Color get _accent => _isEco ? Colors.green.shade600 : const Color(0xFF2CA5E0);

  String _titleText(AppLocalizations l10n) =>
      _isEco ? l10n.aiTitleEco : l10n.aiTitleAnalyze;

  String _hintText(AppLocalizations l10n) =>
      _isEco ? l10n.aiHintEco : l10n.aiHint;

  String _errorText(AppLocalizations l10n, AiErrorKind kind) {
    switch (kind) {
      case AiErrorKind.unavailable:
        return l10n.aiErrorUnavailable;
      case AiErrorKind.timeout:
        return l10n.aiErrorTimeout;
      case AiErrorKind.generic:
        return l10n.aiErrorGeneric;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _takePicture());
    }
  }

  Future<void> _pickSource(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);

    await showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF2CA5E0)),
              title: Text(l10n.fromGallery, style: TextStyle(color: textColor)),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage();
              },
            ),
            if (!_isEco)
              ListTile(
                leading: Icon(Icons.picture_as_pdf, color: Colors.red.shade400),
                title: Text(l10n.importPdfDocument, style: TextStyle(color: textColor)),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickPdf();
                },
              ),
            ListTile(
              leading: Icon(Icons.camera_alt_outlined, color: Colors.green.shade400),
              title: Text(l10n.wmTakePhoto, style: TextStyle(color: textColor)),
              onTap: () async {
                Navigator.pop(context);
                await _takePicture();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) _setImage(File(picked.path));
  }

  Future<void> _takePicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked != null) _setImage(File(picked.path));
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result?.files.first.path == null) return;
    final imageFile = await _renderPdfPage(File(result!.files.first.path!));
    _setImage(imageFile);
  }

  Future<File> _renderPdfPage(File pdfFile) async {
    final pdfDoc = await PdfDocument.openFile(pdfFile.path);
    final page = pdfDoc.pages[0];
    final pdfImage = await page.render(
      fullWidth: page.width * 2,
      fullHeight: page.height * 2,
    );
    final image = img.Image.fromBytes(
      width: pdfImage!.width,
      height: pdfImage.height,
      bytes: pdfImage.pixels.buffer,
      order: img.ChannelOrder.bgra,
    );
    pdfImage.dispose();
    await pdfDoc.dispose();
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/ai_tmp.png';
    await File(path).writeAsBytes(Uint8List.fromList(img.encodePng(image)));
    return File(path);
  }

  void _setImage(File file) {
    setState(() {
      _imageFile = file;
      _result = null;
      _errorKind = null;
    });
  }

  Future<void> _analyze() async {
    if (_imageFile == null) return;
    setState(() {
      _isLoading = true;
      _result = null;
      _errorKind = null;
    });
    try {
      final result = _isEco
          ? await AIService().analyzeEcoPackaging(_imageFile!)
          : await AIService().analyzeDocument(_imageFile!);
      if (mounted) setState(() => _result = result);
    } on AiException catch (e) {
      if (mounted) setState(() => _errorKind = e.kind);
    } catch (_) {
      if (mounted) setState(() => _errorKind = AiErrorKind.generic);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        title: Text(_titleText(l10n)),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Шапка-подсказка: что делает этот экран.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_accent.withValues(alpha: 0.16), _accent.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_isEco ? Icons.eco : Icons.auto_awesome, color: _accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _hintText(l10n),
                    style: TextStyle(fontSize: 13, color: textColor, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          GestureDetector(
            onTap: () => _pickSource(context),
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _imageFile != null
                      ? _accent.withValues(alpha: 0.5)
                      : (isDark ? Colors.white12 : const Color(0xFFE8EDF5)),
                  width: _imageFile != null ? 1.5 : 1,
                ),
              ),
              child: _imageFile != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Image.file(_imageFile!,
                              fit: BoxFit.cover, width: double.infinity, height: 220),
                        ),
                        Positioned(
                          right: 8, top: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.refresh, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(l10n.wmChange,
                                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isEco ? Icons.eco : Icons.document_scanner,
                            size: 32,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _isEco ? l10n.aiSelectEcoPhoto : l10n.aiSelectDocOrPhoto,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.aiTapToSelect,
                          style: TextStyle(fontSize: 12, color: subColor),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickSource(context),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_imageFile != null ? l10n.wmChange : l10n.aiSelectFile),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_imageFile == null || _isLoading) ? null : _analyze,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_isEco ? Icons.eco : Icons.auto_awesome, size: 18),
                  label: Text(_isLoading ? l10n.aiAnalyzing : l10n.aiAnalyze),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),

          // Состояние загрузки.
          if (_isLoading) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 30, height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent),
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.aiAnalyzing, style: TextStyle(fontSize: 14, color: subColor)),
                ],
              ),
            ),
          ],

          // Чистая карточка ошибки вместо сырого DioException + повтор.
          if (_errorKind != null && !_isLoading) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: isDark ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade400, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    _errorText(l10n, _errorKind!),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _analyze,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.actionRetry),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_result != null && !_isLoading) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accent.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_isEco ? Icons.eco : Icons.auto_awesome, size: 18, color: _accent),
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiResultTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SelectableText(
                    _result!,
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.55),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
