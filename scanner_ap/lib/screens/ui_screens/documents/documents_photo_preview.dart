import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'document_camera_edit.dart';
import '../../../l10n/app_localizations.dart';

class MultiPageDocumentPreviewScreen extends StatelessWidget {
  final List<XFile> imageFiles;
  final void Function(List<String> editedPaths)? onSaveBatch; 
  final void Function()? onRetakeAll; 

  const MultiPageDocumentPreviewScreen({
    super.key,
    required this.imageFiles,
    this.onSaveBatch,
    this.onRetakeAll,
  });

  Widget _buildImagePreview(BuildContext context, XFile file, int index) {
    final l10n = AppLocalizations.of(context);
    final double screenWidth = MediaQuery.of(context).size.width;

    const double aspectRatio = 1 / 1.414;

    final double containerWidth = screenWidth - 32.0;

    final double calculatedHeight = containerWidth / aspectRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            l10n.docPageNofM(index + 1, imageFiles.length),
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
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 60, bottom: 120),
                itemCount: imageFiles.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 20),
                    child: _buildImagePreview(context, imageFiles[index], index),
                  );
                },
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
            child: Padding( 
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded( 
                    child: ElevatedButton.icon(
                      onPressed: onRetakeAll,
                      icon: const Icon(Icons.delete_forever, color: Colors.white),
                      label: Text(AppLocalizations.of(context).docResetBatch, overflow: TextOverflow.ellipsis),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),

                
                  Expanded( 
                    child: ElevatedButton.icon(
                      onPressed: () {
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            
                            builder: (_) => DocumentCameraEditScreen(
                              imageFiles: imageFiles,
                              onSave: (editedPaths) {
                                
                                Navigator.popUntil(context, (route) => route.isFirst);
                                if (onSaveBatch != null) {
                                  onSaveBatch!(editedPaths);
                                }
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.edit_note, color: Colors.white),
                      label: Text(
                        AppLocalizations.of(context).editCount(imageFiles.length),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        
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