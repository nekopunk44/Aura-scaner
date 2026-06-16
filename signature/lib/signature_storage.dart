import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignatureStorage {
  static const _signatureStorageKey = 'signature_image_base64';

  const SignatureStorage({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<Uint8List?> loadSignature() async {
    await _ensureMigrated();
    final encoded = await _secureStorage.read(key: _signatureStorageKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveSignature(Uint8List bytes) async {
    await _ensureMigrated();
    await _secureStorage.write(
      key: _signatureStorageKey,
      value: base64Encode(bytes),
    );
  }

  Future<void> clearSignature() async {
    await _ensureMigrated();
    await _secureStorage.delete(key: _signatureStorageKey);
  }

  Future<void> _ensureMigrated() async {
        final prefs = await SharedPreferences.getInstance();
        final secureValue = await _secureStorage.read(key: _signatureStorageKey);
        if (secureValue != null && secureValue.isNotEmpty) {
          await prefs.remove(_signatureStorageKey);
          return;
        }

        final legacyValue = prefs.getString(_signatureStorageKey);
        if (legacyValue != null && legacyValue.isNotEmpty) {
          await _secureStorage.write(
            key: _signatureStorageKey,
            value: legacyValue,
          );
          await prefs.remove(_signatureStorageKey);
        }
      }
}
