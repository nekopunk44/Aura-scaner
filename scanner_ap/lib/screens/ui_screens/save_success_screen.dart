// save_success_screen.dart (БЕЗ ИЗМЕНЕНИЙ, кроме импорта)

import 'package:flutter/material.dart';
import 'main_screen/app_tabs_screen.dart';
import 'passport/save_options_passport.dart'; 

class SaveSuccessScreen extends StatelessWidget {
  final String filePath;
  final SaveFormat format;

  const SaveSuccessScreen({
    super.key,
    required this.filePath,
    required this.format,
  });

  String get _formatText {
    return format == SaveFormat.pdf ? 'PDF-файл' : 'Фото/Изображение';
  }

  @override
  Widget build(BuildContext context) {
   

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 100),
              const SizedBox(height: 20),
              const Text(
                'Документ сохранен!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '$_formatText успешно сохранено и доступно в разделе "Мои файлы".',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => MainScreen()),
                        (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Перейти в "Мои файлы"',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}