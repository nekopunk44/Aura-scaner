// id_card_photo_preview.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'id_card_photo_edit.dart';
import '../../../l10n/app_localizations.dart';

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

  Widget _buildImagePreview(BuildContext context, XFile file, String label) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double containerWidth = screenWidth - 32.0;

    const double aspectRatio = 1.6;

    final double calculatedHeight = containerWidth / aspectRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),

        Container(
          height: calculatedHeight,
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2A3A),
            border: Border.all(
                color: const Color(0xFF2CA5E0).withValues(alpha: 0.35), width: 1.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.5),
            child: Image.file(
              File(file.path),
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F1923),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 120),
                  child: Column(
                    children: [
                      // Первая сторона
                      _buildImagePreview(context, frontImage, l10n.frontSide),

                      const SizedBox(height: 20),

                      // Вторая сторона
                      _buildImagePreview(context, backImage, l10n.backSide),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Нижняя панель: затемнение-градиент + две кнопки во всю ширину.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16, 24, 16, 20 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Переснять — вторичная кнопка (уже, текст короткий).
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: onRetake,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.28)),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.refresh, size: 19),
                              const SizedBox(width: 8),
                              Text(l10n.camRetake,
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Редактировать — основная кнопка (шире, акцент).
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IdCardPhotoEditScreen(
                                frontImage: frontImage,
                                backImage: backImage,
                                onSave: (editedPaths) {
                                  Navigator.popUntil(
                                      context, (route) => route.isFirst);
                                  onConfirm();
                                },
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, size: 20),
                              const SizedBox(width: 8),
                              Text(l10n.editCount(2),
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}