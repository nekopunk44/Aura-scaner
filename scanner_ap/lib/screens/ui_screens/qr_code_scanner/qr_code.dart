import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

/// Экран сканирования QR-кодов.
///
/// После успешного сканирования:
/// - Приостанавливает камеру
/// - Показывает содержимое QR-кода
/// - Если содержимое — ссылка (http/https/другой протокол), открывает в браузере
/// - Через 3 секунды возобновляет сканирование
///
/// Для URL без протокола автоматически добавляет "https://".
class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({super.key});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: "QR");
  Barcode? result;
  QRViewController? controller;

  bool _isLaunching = false;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: QRView(key: qrKey, onQRViewCreated: _onQrViewCreated),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: (result != null)
                  ? Text("Barcode Data: ${result!.code ?? 'Нет данных'}")
                  : const Text("Сканируйте QR-код"),
            ),
          ),
        ],
      ),
    );
  }

  void _onQrViewCreated(QRViewController controller) {
    this.controller = controller;

    controller.scannedDataStream.listen((scanData) {
      String? code = scanData.code;

      if (code != null && !_isLaunching) {
        _isLaunching = true;
        controller.pauseCamera();

        setState(() {
          result = scanData;
        });

        _launchInBrowser(code);

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _isLaunching = false;
            controller.resumeCamera();
            setState(() {
              result = null; 
            });
          }
        });
      }
    });
  }

  void _launchInBrowser(String string) async {
    String urlString = string;

    if (!urlString.toLowerCase().startsWith('http://') &&
        !urlString.toLowerCase().startsWith('https://') &&
        !urlString.toLowerCase().startsWith('mailto:') &&
        !urlString.toLowerCase().startsWith('tel:')) {
      urlString = 'https://$string';
    }

    Uri? uri = Uri.tryParse(urlString);

    try {
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception("Invalid URI format: $string");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Невозможно открыть ссылку: $string."),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}