import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/signature_storage_service.dart';
import 'signature_pad.dart';

class SignaturePickerSheet extends StatefulWidget {
  final SignatureStorageService storage;

  const SignaturePickerSheet({super.key, required this.storage});

  static Future<Uint8List?> pickSignature(
    BuildContext context, {
    required SignatureStorageService storage,
  }) async {
    final signatures = await storage.loadSignatures();
    if (!context.mounted) return null;

    if (signatures.length == 1) {
      return signatures.first.bytes;
    }

    return showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SignaturePickerSheet(storage: storage),
    );
  }

  @override
  State<SignaturePickerSheet> createState() => _SignaturePickerSheetState();
}

class _SignaturePickerSheetState extends State<SignaturePickerSheet> {
  static const _maxSheetHeightFactor = 0.72;
  static const _headerHeightEstimate = 136.0;
  static const _gridHorizontalPadding = 40.0;
  static const _gridCrossAxisSpacing = 12.0;
  static const _gridMainAxisSpacing = 12.0;
  static const _gridChildAspectRatio = 1.35;

  List<StoredSignature> _signatures = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignatures();
  }

  Future<void> _loadSignatures() async {
    final signatures = await widget.storage.loadSignatures();
    if (!mounted) return;
    setState(() {
      _signatures = signatures;
      _isLoading = false;
    });
  }

  Future<void> _createNewSignature() async {
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (!mounted || result == null) return;

    await widget.storage.addSignature(result);
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  double _gridHeight(BuildContext context) {
    final rows = (_signatures.length / 2).ceil();
    final width = MediaQuery.sizeOf(context).width;
    final availableWidth =
        width - _gridHorizontalPadding - _gridCrossAxisSpacing;
    final itemWidth = availableWidth <= 0 ? 0.0 : availableWidth / 2;
    final itemHeight = itemWidth / _gridChildAspectRatio;
    return 28 + rows * itemHeight + (rows - 1) * _gridMainAxisSpacing;
  }

  Widget _buildBody({
    required AppLocalizations l10n,
    required Color textColor,
    required Color subColor,
    required bool isDark,
    required double maxHeight,
  }) {
    if (_isLoading) {
      return const SizedBox(
        height: 128,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_signatures.isEmpty) {
      return SizedBox(
        height: 270,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.draw_outlined, size: 56, color: subColor),
                const SizedBox(height: 12),
                Text(
                  l10n.sigAddYours,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.sigDrawFinger,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subColor),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _createNewSignature,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2CA5E0),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.sigAdd),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final contentHeight = _gridHeight(context);
    final shouldScroll = contentHeight > maxHeight;

    return SizedBox(
      height: shouldScroll ? maxHeight : contentHeight,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        physics: shouldScroll
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: _gridCrossAxisSpacing,
          mainAxisSpacing: _gridMainAxisSpacing,
          childAspectRatio: _gridChildAspectRatio,
        ),
        itemCount: _signatures.length,
        itemBuilder: (context, index) {
          final signature = _signatures[index];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(context, signature.bytes),
            child: Ink(
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : const Color(0xFFF5F8FC),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF2CA5E0).withValues(alpha: 0.18),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localizations.localeOf(context).languageCode == 'ru'
                          ? 'Подпись ${index + 1}'
                          : 'Signature ${index + 1}',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Image.memory(
                          signature.bytes,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF182434) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSheetHeight = constraints.maxHeight * _maxSheetHeightFactor;
          final maxBodyHeight = (maxSheetHeight - _headerHeightEstimate).clamp(
            128.0,
            maxSheetHeight,
          );

          return Container(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Localizations.localeOf(context).languageCode ==
                                      'ru'
                                  ? 'Выберите подпись'
                                  : 'Choose signature',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              Localizations.localeOf(context).languageCode ==
                                      'ru'
                                  ? 'Можно использовать сохраненную или создать новую'
                                  : 'Use a saved one or create a new signature',
                              style: TextStyle(color: subColor, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: _createNewSignature,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2CA5E0),
                          foregroundColor: Colors.white,
                          fixedSize: const Size(48, 48),
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder(),
                        ),
                        child: const Icon(Icons.add, size: 24),
                      ),
                    ],
                  ),
                ),
                _buildBody(
                  l10n: l10n,
                  textColor: textColor,
                  subColor: subColor,
                  isDark: isDark,
                  maxHeight: maxBodyHeight.toDouble(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
