import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  SignatureController signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(title: const Text('Добавить подпись')),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Signature(
                height: MediaQuery.of(context).size.width,
                width: MediaQuery.of(context).size.width,
                controller: signatureController,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                padButtonOption(Colors.redAccent, 'Очистить', () {
                  signatureController.clear();
                }),
                padButtonOption(Colors.greenAccent, 'Готово', () async {
                  if (signatureController.isNotEmpty) {
                    final signature = await exportSignature();
                    if (signature.isNotEmpty) {
                      if (!context.mounted) return;
                      Navigator.pop(context, signature);
                    }
                  }
                }),
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
    return signature!;
  }

  ElevatedButton padButtonOption(
    Color btnClr,
    String btnTxt,
    Function() btnOnTapAction,
  ) {
    return ElevatedButton(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(btnClr),
        padding: WidgetStateProperty.all(const EdgeInsets.all(20)),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 14, color: Colors.white),
        ),
      ),
      onPressed: btnOnTapAction,
      child: Text(btnTxt),
    );
  }
}
