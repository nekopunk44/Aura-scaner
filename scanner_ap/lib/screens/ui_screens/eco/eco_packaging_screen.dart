import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/eco_report.dart';
import '../../../services/ai_service.dart';
import '../../../services/eco_history_service.dart';
import '../../../services/eco_pdf_service.dart';
import 'eco_history_screen.dart';
import 'eco_report_view.dart';

/// Премиальный «Эко-сканер» упаковки: фото → структурированный отчёт
/// (эко-балл, материалы, переработка, значки), экспорт в PDF и история.
class EcoPackagingScreen extends StatefulWidget {
  final bool autoCamera;
  const EcoPackagingScreen({super.key, this.autoCamera = false});

  @override
  State<EcoPackagingScreen> createState() => _EcoPackagingScreenState();
}

class _EcoPackagingScreenState extends State<EcoPackagingScreen> {
  static const _accent = Color(0xFF16A34A);

  File? _imageFile;
  EcoReport? _report;
  AiErrorKind? _errorKind;
  bool _isLoading = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _takePicture());
    }
  }

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

  Future<void> _pickSource() async {
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
              leading: const Icon(Icons.photo_library_outlined, color: _accent),
              title: Text(l10n.fromGallery, style: TextStyle(color: textColor)),
              onTap: () async {
                Navigator.pop(context);
                await _pickImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: _accent),
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

  void _setImage(File file) {
    setState(() {
      _imageFile = file;
      _report = null;
      _errorKind = null;
    });
  }

  Future<void> _analyze() async {
    final file = _imageFile;
    if (file == null) return;
    setState(() {
      _isLoading = true;
      _report = null;
      _errorKind = null;
    });
    try {
      final report = await AIService().analyzeEcoReport(file);
      if (!mounted) return;
      setState(() => _report = report);
      // Сохраняем в локальную историю (миниатюра + отчёт).
      await EcoHistoryService().add(file, report);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).ecoSavedToHistory)),
        );
      }
    } on AiException catch (e) {
      if (mounted) setState(() => _errorKind = e.kind);
    } catch (_) {
      if (mounted) setState(() => _errorKind = AiErrorKind.generic);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null || _exporting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _exporting = true);
    try {
      await EcoPdfService().shareReport(report, l10n, sourceImage: _imageFile);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.aiErrorGeneric)),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _buildBenefits(
    AppLocalizations l10n,
    Color cardBg,
    Color textColor,
    Color subColor,
  ) {
    final items = <({IconData icon, Color color, String text})>[
      (icon: Icons.verified_outlined, color: const Color(0xFF16A34A), text: l10n.ecoBenefitScore),
      (icon: Icons.recycling, color: const Color(0xFF0D9488), text: l10n.ecoBenefitRecycle),
      (icon: Icons.qr_code_2, color: const Color(0xFF2563EB), text: l10n.ecoBenefitMarks),
      (icon: Icons.picture_as_pdf_outlined, color: const Color(0xFFDC2626), text: l10n.ecoBenefitPdf),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.ecoBenefitsTitle,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: textColor),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: items[i].color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(items[i].icon, color: items[i].color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    items[i].text,
                    style: TextStyle(fontSize: 13.5, color: textColor, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
        ],
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
        title: Text(l10n.ecoTitle),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.ecoHistoryOpen,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EcoHistoryScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Превью/выбор фото.
          GestureDetector(
            onTap: _pickSource,
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
                          child: const Icon(Icons.eco, size: 32, color: _accent),
                        ),
                        const SizedBox(height: 14),
                        Text(l10n.aiSelectEcoPhoto,
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                        const SizedBox(height: 4),
                        Text(l10n.aiTapToSelect,
                            style: TextStyle(fontSize: 12, color: subColor)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Кнопка анализа на всю ширину (выбор фото — по тапу на блок выше).
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_imageFile == null || _isLoading) ? null : _analyze,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.eco, size: 18),
              label: Text(_isLoading ? l10n.aiAnalyzing : l10n.aiAnalyze),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _accent.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // Пустое состояние: показываем ценность фичи, а не пустоту.
          if (_imageFile == null &&
              _report == null &&
              _errorKind == null &&
              !_isLoading) ...[
            const SizedBox(height: 24),
            _buildBenefits(l10n, cardBg, textColor, subColor),
          ],

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
                  const SizedBox(
                    width: 30, height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent),
                  ),
                  const SizedBox(height: 14),
                  Text(l10n.aiAnalyzing, style: TextStyle(fontSize: 14, color: subColor)),
                ],
              ),
            ),
          ],

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
                  Text(_errorText(l10n, _errorKind!),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: textColor, height: 1.4)),
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

          if (_report != null && !_isLoading) ...[
            const SizedBox(height: 20),
            EcoReportView(report: _report!),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(l10n.ecoExportPdf),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
