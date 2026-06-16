import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'signature_pad.dart';
import '../../../services/document_registry.dart';
import '../../../services/signature_storage_service.dart';
import '../../../l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _signatureStorage = SignatureStorageService();

  Uint8List? signatureImage;
  String? savedPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final storedSignature = await _signatureStorage.loadSignature();
    if (!mounted) return;
    setState(() {
      signatureImage = storedSignature;
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
    await _signatureStorage.saveSignature(bytes);
    if (!mounted) return;

    setState(() {
      signatureImage = bytes;
      savedPath = null;
    });
  }

  Future<void> _clearSavedSignature() async {
    await _signatureStorage.clearSignature();
    if (!mounted) return;
    setState(() {
      signatureImage = null;
      savedPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.featSignature, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
        backgroundColor: appBarBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          if (savedPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.green.shade400),
                    const SizedBox(width: 4),
                    Text(
                      l10n.savedPlain,
                      style: TextStyle(
                          color: Colors.green.shade400, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (signatureImage == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF2CA5E0).withValues(alpha: 0.2),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(Icons.draw_outlined, size: 52,
                        color: const Color(0xFF2CA5E0).withValues(alpha: 0.6)),
                    const SizedBox(height: 12),
                    Text(l10n.sigAddYours,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: textColor)),
                    const SizedBox(height: 4),
                    Text(l10n.sigDrawFinger,
                        style: TextStyle(fontSize: 13, color: subColor)),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    signatureImage!,
                    height: MediaQuery.of(context).size.width - 40,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                icon: Icon(
                    signatureImage == null ? Icons.draw : Icons.edit, size: 18),
                label: Text(
                    signatureImage == null ? l10n.sigAdd : l10n.sigChange),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2CA5E0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  await _openSignaturePad();
                },
              ),
            ),
            if (signatureImage != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(l10n.sigSaveToFiles),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    disabledBackgroundColor:
                        Colors.green.shade600.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: savedPath != null
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await _saveSignatureToFile(signatureImage!);
                          if (!mounted) return;
                          messenger.showSnackBar(SnackBar(
                            content: Text(l10n.sigSavedToMyFiles),
                            backgroundColor: Colors.green,
                          ));
                        },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(AppLocalizations.of(context).clearSelection),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    side: BorderSide(color: Colors.red.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _clearSavedSignature,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
