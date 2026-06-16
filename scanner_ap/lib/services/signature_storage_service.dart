import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SignatureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _signatureKey = 'saved_signature_image_base64';

  Future<Uint8List?> loadSignature() async {
    final encoded = await _storage.read(key: _signatureKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveSignature(Uint8List bytes) async {
    await _storage.write(key: _signatureKey, value: base64Encode(bytes));
  }

  Future<void> clearSignature() async {
    await _storage.delete(key: _signatureKey);
  }
}
