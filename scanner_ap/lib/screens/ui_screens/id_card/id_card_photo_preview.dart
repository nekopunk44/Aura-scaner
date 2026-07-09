// id_card_photo_preview.dart

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'id_card_photo_edit.dart';

/// Превью обеих сторон ID-карты в фирменном стиле приложения:
/// тёмный градиентный фон, карточки сторон с тенью и чипом-подписью,
/// стеклянная шапка и кнопки действий как в превью паспорта.
class IdCardPhotoPreviewScreen extends StatelessWidget {
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

  void _openEditor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IdCardPhotoEditScreen(
          frontImage: frontImage,
          backImage: backImage,
          onSave: (editedPaths) {
            Navigator.popUntil(context, (route) => route.isFirst);
            onConfirm();
          },
        ),
      ),
    );
  }

  Widget _buildSideCard(BuildContext context, XFile file, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
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
          // Чип-подпись стороны.
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
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
              // ── Шапка: закрыть + заголовок + подзаголовок ───────────────
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
                      child: Column(
                        children: [
                          Text(
                            l10n.previewTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            l10n.previewPagesCount(2),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Симметричный спейсер под ширину кнопки закрытия.
                    const SizedBox(width: 42),
                  ],
                ),
              ),

              // ── Карточки сторон ─────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      _buildSideCard(context, frontImage, l10n.frontSide),
                      const SizedBox(height: 18),
                      _buildSideCard(context, backImage, l10n.backSide),
                    ],
                  ),
                ),
              ),

              // ── Действия ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: onRetake,
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(l10n.camRetake),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.30),
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
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
                                color: const Color(0xFF26C060)
                                    .withValues(alpha: 0.38),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => _openEditor(context),
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 20),
                            label: Text(
                              l10n.editCount(2),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
