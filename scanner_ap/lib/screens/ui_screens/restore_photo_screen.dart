import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

const _documentKey = 'saved_document_paths';

class RestorePhotoScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const RestorePhotoScreen({super.key, this.onSaved});

  @override
  State<RestorePhotoScreen> createState() => _RestorePhotoScreenState();
}

class _RestorePhotoScreenState extends State<RestorePhotoScreen> {
  File? _selectedFile;
  File? _previewFile;
  bool _isProcessing = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedFile = File(picked.path);
        _previewFile = File(picked.path);
      });
    }
  }

  Future<void> _autoEnhance() async {
    if (_selectedFile == null) return;
    setState(() => _isProcessing = true);
    try {
      final bytes = await _selectedFile!.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return;

      final sharpened = img.convolution(
        image,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
        div: 1,
        offset: 0,
      );
      final enhanced = img.adjustColor(
        sharpened,
        contrast: 1.1,
        brightness: 1.05,
        saturation: 1.1,
      );

      final dir = await getApplicationDocumentsDirectory();
      final name = 'restored_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '${dir.path}/$name';
      await File(path).writeAsBytes(Uint8List.fromList(img.encodeJpg(enhanced, quality: 92)));

      setState(() => _previewFile = File(path));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openEditor() async {
    if (_previewFile == null) return;
    final bytes = await _previewFile!.readAsBytes();
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditor(image: bytes),
      ),
    );
    if (result != null && result is Uint8List && mounted) {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(result);
      setState(() => _previewFile = File(path));
    }
  }

  Future<void> _save() async {
    if (_previewFile == null) return;
    setState(() => _isProcessing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'restored_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = '${dir.path}/$name';
      await _previewFile!.copy(dest);

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_documentKey) ?? [];
      if (!paths.contains(dest)) {
        paths.add(dest);
        await prefs.setStringList(_documentKey, paths);
      }

      widget.onSaved?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).savedPlain), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
        title: Text(l10n.featRestorePhoto),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _previewFile != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(_previewFile!, fit: BoxFit.contain),
                    ),
                  )
                : Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        margin: const EdgeInsets.all(32),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF2CA5E0).withValues(alpha: 0.3),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined,
                                size: 52, color: const Color(0xFF2CA5E0)),
                            const SizedBox(height: 12),
                            Text(l10n.importChoosePhoto,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: textColor)),
                            const SizedBox(height: 4),
                            Text('JPG, PNG',
                                style: TextStyle(fontSize: 13, color: subColor)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (_previewFile != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _autoEnhance,
                            icon: const Icon(Icons.auto_fix_high, size: 18),
                            label: Text(l10n.restoreAuto),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2CA5E0),
                              side: const BorderSide(color: Color(0xFF2CA5E0)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _openEditor,
                            icon: const Icon(Icons.edit, size: 18),
                            label: Text(l10n.restoreEditor),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textColor,
                              side: BorderSide(
                                  color: isDark ? Colors.white24 : const Color(0xFFDDE3ED)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2CA5E0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(l10n.actionSave,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
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
