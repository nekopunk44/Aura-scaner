import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart' as spdf;
import '../../l10n/app_localizations.dart';

class AddPasswordScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const AddPasswordScreen({super.key, this.onSaved});

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  File? _selectedFile;
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isProcessing = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.first.path != null) {
      setState(() => _selectedFile = File(result.files.first.path!));
    }
  }

  Future<void> _protect() async {
    final l10n = AppLocalizations.of(context);
    if (_selectedFile == null) {
      _snack(l10n.pwdSelectPdf);
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      _snack(l10n.validatePasswordRequired);
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
      _snack(l10n.pwdMismatch);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final bytes = await _selectedFile!.readAsBytes();
      final doc = spdf.PdfDocument(inputBytes: bytes);

      doc.security.ownerPassword = _passwordCtrl.text;
      doc.security.userPassword = _passwordCtrl.text;
      doc.security.algorithm = spdf.PdfEncryptionAlgorithm.aesx256Bit;

      final saved = await doc.save();
      doc.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final baseName = p.basenameWithoutExtension(_selectedFile!.path);
      final outPath = '${dir.path}/${baseName}_protected.pdf';
      await File(outPath).writeAsBytes(saved);

      widget.onSaved?.call();
      if (mounted) {
        _snack(l10n.snackSaved(p.basename(outPath)), success: true);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('${l10n.commonError}: $e', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _snack(String msg, {bool success = false, bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : (error ? Colors.red : null),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white54 : const Color(0xFF6B7A99);
    final inputFill = isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF2F6FC);
    final inputBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE8EDF5);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(l10n.featAddPassword),
        backgroundColor: isDark ? const Color(0xFF141E2B) : Colors.white,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.importPdfDocument, style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _pickPdf,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: inputFill,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedFile != null
                            ? const Color(0xFF2CA5E0)
                            : inputBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf,
                            color: _selectedFile != null ? const Color(0xFF2CA5E0) : subColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedFile != null
                                ? p.basename(_selectedFile!.path)
                                : l10n.pwdSelectPdfFile,
                            style: TextStyle(
                              color: _selectedFile != null ? textColor : subColor,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: subColor, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.fieldPassword, style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                _PasswordField(
                  controller: _passwordCtrl,
                  hint: l10n.validatePasswordRequired,
                  obscure: _obscurePassword,
                  onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                  isDark: isDark,
                  inputFill: inputFill,
                  inputBorder: inputBorder,
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _confirmCtrl,
                  hint: l10n.pwdRepeatPassword,
                  obscure: _obscureConfirm,
                  onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  isDark: isDark,
                  inputFill: inputFill,
                  inputBorder: inputBorder,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _protect,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2CA5E0),
                disabledBackgroundColor: const Color(0xFF2CA5E0).withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.pwdProtectAction,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final bool isDark;
  final Color inputFill;
  final Color inputBorder;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    required this.isDark,
    required this.inputFill,
    required this.inputBorder,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final hintColor = isDark ? Colors.white38 : Colors.grey.shade400;
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor),
        prefixIcon: Icon(Icons.lock_outline, size: 20,
            color: isDark ? Colors.white38 : Colors.grey.shade400),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20, color: isDark ? Colors.white38 : Colors.grey.shade400),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: inputBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: inputBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2CA5E0), width: 1.5)),
      ),
    );
  }
}
