import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'signature_pad.dart';
import 'signature_storage.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, SignatureStorage? storage})
      : storage = storage ?? const SignatureStorage();

  final SignatureStorage storage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? signatureImage;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final signature = await widget.storage.loadSignature();
    if (!mounted) return;
    setState(() {
      signatureImage = signature;
      isLoading = false;
    });
  }

  Future<void> _saveSignature(Uint8List bytes) async {
    await widget.storage.saveSignature(bytes);
  }

  Future<void> _clearSignature() async {
    await widget.storage.clearSignature();
    if (!mounted) return;
    setState(() {
      signatureImage = null;
    });
  }

  Future<void> _openSignaturePad() async {
    final result = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (!mounted || result == null) return;
    await _saveSignature(result);
    setState(() {
      signatureImage = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aura Signature')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black12),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 16,
                            color: Color(0x11000000),
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: signatureImage == null
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Add your signature once to save it and reuse it later.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Image.memory(
                                  signatureImage!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _openSignaturePad,
                    child: Text(
                      signatureImage == null
                          ? 'Add Signature'
                          : 'Update Signature',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: signatureImage == null ? null : _clearSignature,
                    child: const Text('Delete Signature'),
                  ),
                ],
              ),
            ),
    );
  }
}
