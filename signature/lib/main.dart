import 'package:flutter/material.dart';

import 'home_screen.dart';

void main() {
  runApp(const SignatureApp());
}

class SignatureApp extends StatelessWidget {
  const SignatureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Signature',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C86)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
