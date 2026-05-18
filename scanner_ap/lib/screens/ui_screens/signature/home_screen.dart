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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подпись'),
        actions: [
          if (savedPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Сохранено',
                  style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (signatureImage == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Добавьте свою подпись',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              )
            else
              Image.memory(
                signatureImage!,
                height: MediaQuery.of(context).size.width,
                width: MediaQuery.of(context).size.width,
                fit: BoxFit.contain,
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit, color: Colors.white),
              label: Text(
                signatureImage == null ? 'Добавить подпись' : 'Изменить подпись',
                style: const TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            if (signatureImage != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('Сохранить в файлы', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: savedPath != null
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await _saveSignatureToFile(signatureImage!);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Подпись сохранена в "Мои файлы"'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
