// PhotoPreviewScreen.dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'photo_edit_passport.dart';
import '../../../l10n/app_localizations.dart';

class PhotoPreviewScreen extends StatelessWidget {
  final XFile imageFile;
  final XFile? secondImageFile;
  final bool isTwoPageMode;

  final void Function()? onConfirm;
  final void Function()? onRetake;

  const PhotoPreviewScreen({
    super.key,
    required this.imageFile,
    this.secondImageFile,
    this.isTwoPageMode = false,
    this.onConfirm,
    this.onRetake,
  });

  Widget _buildImagePreview(BuildContext context, XFile file, int index) {
    final l10n = AppLocalizations.of(context);
    final double screenWidth = MediaQuery.of(context).size.width;
    final double containerWidth = screenWidth - 32.0;

    const double aspectRatio = 0.70;

    final double calculatedHeight = containerWidth / aspectRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            l10n.pageLabel(index),
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
    final l10n = AppLocalizations.of(context);
    final List<XFile> filesToEdit = [imageFile];
    if (isTwoPageMode && secondImageFile != null) {
      filesToEdit.add(secondImageFile!);
    }

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
                      _buildImagePreview(context, imageFile, 1),

                      if (isTwoPageMode && secondImageFile != null) ...[
                        const SizedBox(height: 20),
                        _buildImagePreview(context, secondImageFile!, 2),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetake,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: Text(l10n.actionRetry),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PhotoEditScreen(
                          imageFiles: filesToEdit,
                          onSave: (editedPaths) {
                            Navigator.popUntil(context, (route) => route.isFirst);
                            if (onConfirm != null) {
                              onConfirm!();
                            }
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(filesToEdit.length > 1 ? l10n.editCount(filesToEdit.length) : l10n.passportUseButton),
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