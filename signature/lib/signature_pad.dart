import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final SignatureController signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  @override
  void dispose() {
    signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Draw Signature')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.black12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Signature(
                    controller: signatureController,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(
                  color: Colors.redAccent,
                  label: 'Clear',
                  onTap: signatureController.clear,
                ),
                _actionButton(
                  color: Colors.teal,
                  label: 'Save',
                  onTap: () async {
                    if (signatureController.isEmpty) return;
                    final signature = await exportSignature();
                    if (!mounted || signature.isEmpty) return;
                    navigator.pop(signature);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> exportSignature() async {
    final exportController = SignatureController(
      penStrokeWidth: 5,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
      points: signatureController.points,
    );

    final signature = await exportController.toPngBytes();
    exportController.dispose();
    return signature ?? Uint8List(0);
  }

  ElevatedButton _actionButton({
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(color),
        padding: WidgetStateProperty.all(const EdgeInsets.all(20)),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}
