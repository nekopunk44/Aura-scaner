import 'package:flutter/material.dart';
import 'main_screen/app_tabs_screen.dart';
import '../../models/save_format.dart';
import '../../l10n/app_localizations.dart';

class SaveSuccessScreen extends StatelessWidget {
  final String filePath;
  final SaveFormat format;

  const SaveSuccessScreen({
    super.key,
    required this.filePath,
    required this.format,
  });

  String _formatText(AppLocalizations l10n) =>
      format == SaveFormat.pdf ? l10n.saveFormatPdf : l10n.saveFormatImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7A99);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.green, size: 52),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.saveDocSaved,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.saveSuccessBody(_formatText(l10n)),
                style: TextStyle(fontSize: 15, color: subColor, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const MainScreen()),
                    (route) => false,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2CA5E0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    l10n.saveGoToMyFiles,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
