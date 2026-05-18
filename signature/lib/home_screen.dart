import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'signature_pad.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? signatureImage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            signatureImage == null
                ? const Text(
                    'Добавьте свою подпись',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20.0),
                  )
                : Image.memory(
                    signatureImage!,
                    height: MediaQuery.of(context).size.width,
                    width: MediaQuery.of(context).size.width,
                    fit: BoxFit.fill,
                  ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.green),
                padding: WidgetStateProperty.all(const EdgeInsets.all(20)),
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SignatureScreen()),
                );
                if (!mounted) return;
                setState(() {
                  signatureImage = result;
                });
              },
              child: const Text('Добавить подпись'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
