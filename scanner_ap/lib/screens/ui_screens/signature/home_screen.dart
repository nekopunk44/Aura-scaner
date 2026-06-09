import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'signature_pad.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? signatureImage;
  String? savedPath;

  Future<void> _saveSignatureToFile(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('saved_document_paths') ?? [];
    if (!paths.contains(file.path)) {
      paths.add(file.path);
      await prefs.setStringList('saved_document_paths', paths);
    }

    setState(() => savedPath = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('Подпись', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
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
                      'Сохранено',
                      style: TextStyle(
                          color: Colors.green.shade400, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Padding(
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
                    Text('Добавьте свою подпись',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: textColor)),
                    const SizedBox(height: 4),
                    Text('Нарисуйте подпись пальцем',
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
                    signatureImage == null ? 'Добавить подпись' : 'Изменить подпись'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2CA5E0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignatureScreen()),
                  );
                  if (!mounted || result == null) return;
                  setState(() {
                    signatureImage = result as Uint8List;
                    savedPath = null;
                  });
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
                  label: const Text('Сохранить в файлы'),
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
                          messenger.showSnackBar(const SnackBar(
                            content: Text('Подпись сохранена в "Мои файлы"'),
                            backgroundColor: Colors.green,
                          ));
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
