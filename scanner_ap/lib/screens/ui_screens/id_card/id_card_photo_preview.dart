// id_card_photo_preview.dart

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'id_card_photo_edit.dart';

/// Превью обеих сторон ID-карты: сегмент-переключатель «Лицевая/Обратная»,
/// одна фотография по центру экрана (свайп тоже работает) и кнопка
/// «Редактировать» по центру внизу.
class IdCardPhotoPreviewScreen extends StatefulWidget {
  final XFile frontImage;
  final XFile backImage;

  final void Function() onConfirm;
  final void Function() onRetake;

  const IdCardPhotoPreviewScreen({
    super.key,
    required this.frontImage,
    required this.backImage,
    required this.onConfirm,
    required this.onRetake,
  });

  @override
  State<IdCardPhotoPreviewScreen> createState() =>
      _IdCardPhotoPreviewScreenState();
}

class _IdCardPhotoPreviewScreenState extends State<IdCardPhotoPreviewScreen> {
  final PageController _pageCtrl = PageController();
  int _side = 0; // 0 — лицевая, 1 — обратная

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _selectSide(int side) {
    if (side == _side) return;
    _pageCtrl.animateToPage(
      side,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _openEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IdCardPhotoEditScreen(
          frontImage: widget.frontImage,
          backImage: widget.backImage,
          onSave: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            widget.onConfirm();
          },
        ),
      ),
    );
  }

  Widget _buildSegment(String label, int side) {
    final selected = _side == side;
    return GestureDetector(
      onTap: () => _selectSide(side),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF35B4F4), Color(0xFF1687D5)],
                )
              : null,
          color: selected ? null : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSideCard(XFile file) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            // ID-1 карта: 85.6×54 мм.
            child: AspectRatio(
              aspectRatio: 1.586,
              child: Image.file(
                File(file.path),
                fit: BoxFit.cover,
                width: double.infinity,
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

    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1923), Color(0xFF13253A), Color(0xFF0D2137)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Шапка: закрыть + заголовок ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          l10n.previewTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    // Симметричный спейсер под ширину кнопки закрытия.
                    const SizedBox(width: 42),
                  ],
                ),
              ),

              // ── Сегмент-переключатель сторон ────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSegment(l10n.frontSide, 0),
                      _buildSegment(l10n.backSide, 1),
                    ],
                  ),
                ),
              ),

              // ── Фото выбранной стороны по центру (свайп работает) ───────
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _side = i),
                  children: [
                    _buildSideCard(widget.frontImage),
                    _buildSideCard(widget.backImage),
                  ],
                ),
              ),

              // ── Кнопка «Редактировать» по центру ────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Center(
                  child: SizedBox(
                    width: 240,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF35D07F), Color(0xFF1FA463)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF26C060).withValues(alpha: 0.38),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _openEditor,
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          l10n.actionEdit,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
