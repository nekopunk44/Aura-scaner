// id_card_photo_preview.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'id_card_photo_edit.dart';

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
            border: Border.all(color: Colors.white24, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60, bottom: 120),
                  child: Column(
                    children: [
                      // Первая сторона
                      _buildImagePreview(context, frontImage, 'Лицевая сторона'),

                      const SizedBox(height: 20),

                      // Вторая сторона
                      _buildImagePreview(context, backImage, 'Обратная сторона'),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Кнопка закрытия
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Нижняя панель
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Кнопка Переснять
                ElevatedButton.icon(
                  onPressed: onRetake,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Переснять'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                // Кнопка Редактировать
                ElevatedButton.icon(
                  onPressed: () {
                    // ПЕРЕХОД НА РЕДАКТИРОВАНИЕ ID CARD
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
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: const Text('Редактировать (2)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}