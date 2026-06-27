import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/document_registry.dart';
import '../../../services/signature_storage_service.dart';
import 'signature_pad.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _signatureStorage = SignatureStorageService();

  List<StoredSignature> _signatures = const [];
  String? _selectedSignatureId;
  String? savedPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  bool _isRussian(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'ru';
  }

  StoredSignature? get _selectedSignature {
    if (_selectedSignatureId == null) return null;
    try {
      return _signatures.firstWhere((s) => s.id == _selectedSignatureId);
    } catch (_) {
      return _signatures.isEmpty ? null : _signatures.first;
    }
  }

  Future<void> _loadSignature() async {
    final storedSignatures = await _signatureStorage.loadSignatures();
    if (!mounted) return;
    setState(() {
      _signatures = storedSignatures;
      _selectedSignatureId =
          storedSignatures.isEmpty ? null : storedSignatures.first.id;
      _isLoading = false;
    });
  }

  Future<void> _saveSignatureToFile(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await DocumentRegistry().load();
    await DocumentRegistry().add(
      DocEntry(
        localPath: file.path,
        remoteId: null,
        name: fileName.replaceFirst('.png', ''),
      ),
    );

    setState(() => savedPath = file.path);
  }

  Future<void> _openSignaturePad() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (!mounted || result == null) return;

    final bytes = result as Uint8List;
    final saved = await _signatureStorage.addSignature(bytes);
    if (!mounted) return;

    setState(() {
      _signatures = [saved, ..._signatures];
      _selectedSignatureId = saved.id;
      savedPath = null;
    });
  }

  Future<void> _clearSavedSignature() async {
    final selected = _selectedSignature;
    if (selected == null) return;
    await _signatureStorage.removeSignature(selected.id);
    if (!mounted) return;

    final nextSignatures = _signatures
        .where((signature) => signature.id != selected.id)
        .toList();

    setState(() {
      _signatures = nextSignatures;
      _selectedSignatureId =
          nextSignatures.isEmpty ? null : nextSignatures.first.id;
      savedPath = null;
    });
  }

  String _collectionTitle(BuildContext context) {
    return _isRussian(context) ? 'Коллекция подписей' : 'Signature collection';
  }

  String _collectionSubtitle(BuildContext context) {
    return _isRussian(context)
        ? 'Выберите активную подпись или создайте новую.'
        : 'Choose an active signature or create a new one.';
  }

  String _previewTitle(BuildContext context) {
    return _isRussian(context) ? 'Активная подпись' : 'Active signature';
  }

  String _previewSubtitle(BuildContext context) {
    return _isRussian(context)
        ? 'Эта подпись будет использоваться при вставке в документ.'
        : 'This signature will be used when inserting into a document.';
  }

  String _emptyTitle(BuildContext context) {
    return _isRussian(context) ? 'Добавьте первую подпись' : 'Add your first signature';
  }

  String _emptySubtitle(BuildContext context) {
    return _isRussian(context)
        ? 'Создайте несколько вариантов подписи и быстро выбирайте нужный при вставке в документ.'
        : 'Create several signatures and quickly choose the right one when inserting into a document.';
  }

  String _signatureLabel(BuildContext context, int index) {
    return _isRussian(context) ? 'Подпись ${index + 1}' : 'Signature ${index + 1}';
  }

  String _selectedBadge(BuildContext context) {
    return _isRussian(context) ? 'Активна' : 'Active';
  }

  String _savedBannerText(BuildContext context) {
    return _isRussian(context)
        ? 'Подпись сохранена в файлы'
        : 'Signature saved to files';
  }

  String _tapToSelectLabel(BuildContext context) {
    return _isRussian(context) ? 'Нажмите, чтобы выбрать' : 'Tap to select';
  }

  Widget _buildPreviewCard({
    required BuildContext context,
    required StoredSignature signature,
    required Color titleColor,
    required Color subtitleColor,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1E2B3B), Color(0xFF172332)]
              : const [Colors.white, Color(0xFFF7FAFE)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1624).withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _previewTitle(context),
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _previewSubtitle(context),
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            height: 176,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE6EEF6)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF08111E).withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 2.8,
                  child: Image.memory(
                    signature.bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required BuildContext context,
    required Color cardBg,
    required Color titleColor,
    required Color subtitleColor,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1B2838), Color(0xFF152130)]
              : const [Colors.white, Color(0xFFF6FAFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1624).withValues(alpha: isDark ? 0.24 : 0.07),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF6FCFF5), Color(0xFF2CA5E0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.draw_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            _emptyTitle(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _emptySubtitle(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: subtitleColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg.withValues(alpha: isDark ? 0.65 : 0.8),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              children: [
                _buildFeatureRow(
                  context,
                  icon: Icons.gesture_rounded,
                  title: _isRussian(context) ? 'Рисование пальцем' : 'Finger drawing',
                  subtitle: _isRussian(context)
                      ? 'Создайте естественную подпись прямо на экране.'
                      : 'Create a natural signature directly on the screen.',
                ),
                const SizedBox(height: 14),
                _buildFeatureRow(
                  context,
                  icon: Icons.layers_rounded,
                  title: _isRussian(context) ? 'Несколько вариантов' : 'Multiple variants',
                  subtitle: _isRussian(context)
                      ? 'Храните рабочую, официальную и упрощенную подписи.'
                      : 'Keep work, official, and simplified signature variants.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF2CA5E0).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF2CA5E0), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF6B7A99),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF6B7A99),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing,
        ],
      ],
    );
  }

  Widget _buildGalleryCard(
    BuildContext context, {
    required StoredSignature signature,
    required int index,
    required bool isSelected,
    required Color cardBg,
    required Color titleColor,
    required Color subtitleColor,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () => setState(() {
        _selectedSignatureId = signature.id;
        savedPath = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 136,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: isSelected
              ? const Color(0xFF2CA5E0).withValues(alpha: isDark ? 0.16 : 0.12)
              : cardBg,
          border: Border.all(
            color: isSelected
                ? const Color(0xFF2CA5E0)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE3ECF6)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.16),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _signatureLabel(context, index),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2CA5E0), size: 18),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isSelected ? _selectedBadge(context) : _tapToSelectLabel(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE7EEF7)),
                ),
                child: Image.memory(signature.bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openSignaturePad,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4CB8EE), Color(0xFF2CA5E0)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Text(
                l10n.sigAdd,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectionAddButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSignaturePad,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF2CA5E0).withValues(alpha: isDark ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF2CA5E0).withValues(alpha: 0.24),
            ),
          ),
          child: const Center(
            child: Icon(Icons.add_rounded, color: Color(0xFF2CA5E0), size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enabled = onTap != null;
    final bgColor = isDark ? const Color(0xFF182334) : Colors.white;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: enabled
                      ? accent.withValues(alpha: 0.20)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE3ECF6)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final selectedSignature = _selectedSignature;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text(
          l10n.featSignature,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2CA5E0)))
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: selectedSignature == null
                          ? _buildEmptyState(
                              context: context,
                              cardBg: cardBg,
                              titleColor: textColor,
                              subtitleColor: subColor,
                              isDark: isDark,
                            )
                          : _buildPreviewCard(
                              context: context,
                              signature: selectedSignature,
                              titleColor: textColor,
                              subtitleColor: subColor,
                              isDark: isDark,
                            ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: savedPath == null
                          ? const SizedBox(height: 18)
                          : Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Color(0xFF4CAF50),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _savedBannerText(context),
                                        style: const TextStyle(
                                          color: Color(0xFF4CAF50),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 22),
                    if (_signatures.isEmpty) _buildPrimaryAction(context),
                    if (selectedSignature != null) ...[
                      const SizedBox(height: 0),
                      SizedBox(
                        height: 68,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildActionTile(
                            context,
                            icon: Icons.save_alt_rounded,
                            title: l10n.sigSaveToFiles,
                            subtitle: _isRussian(context)
                                ? 'Экспортировать активную подпись в отдельный PNG-файл.'
                                : 'Export the active signature to a separate PNG file.',
                            accent: const Color(0xFF34A853),
                            onTap: savedPath != null
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    await _saveSignatureToFile(selectedSignature.bytes);
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.sigSavedToMyFiles),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  },
                          ),
                          const SizedBox(width: 12),
                          _buildActionTile(
                            context,
                            icon: Icons.delete_outline_rounded,
                            title: l10n.clearSelection,
                            subtitle: _isRussian(context)
                                ? 'Удалить выбранную подпись из локального хранилища.'
                                : 'Delete the selected signature from local storage.',
                            accent: const Color(0xFFFF6B57),
                            onTap: _clearSavedSignature,
                          ),
                        ],
                        ),
                      ),
                    ],
                    if (_signatures.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _buildSectionHeader(
                        context,
                        title: _collectionTitle(context),
                        subtitle: _collectionSubtitle(context),
                        trailing: _buildCollectionAddButton(context),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 164,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _signatures.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final signature = _signatures[index];
                            return _buildGalleryCard(
                              context,
                              signature: signature,
                              index: index,
                              isSelected: signature.id == _selectedSignatureId,
                              cardBg: cardBg,
                              titleColor: textColor,
                              subtitleColor: subColor,
                              isDark: isDark,
                            );
                          },
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
