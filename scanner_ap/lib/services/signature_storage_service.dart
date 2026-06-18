import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSignature {
  final String id;
  final Uint8List bytes;
  final DateTime createdAt;

  const StoredSignature({
    required this.id,
    required this.bytes,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'bytes': base64Encode(bytes),
        'createdAt': createdAt.toIso8601String(),
      };

  factory StoredSignature.fromJson(Map<String, dynamic> json) {
    return StoredSignature(
      id: json['id'] as String,
      bytes: base64Decode(json['bytes'] as String),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SignatureStorageService {
  static const _storage = FlutterSecureStorage();
  static const _signatureListKey = 'saved_signature_gallery_v2';
  static const _legacySignatureKey = 'saved_signature_image_base64';

  Future<List<StoredSignature>> loadSignatures() async {
    final encodedList = await _storage.read(key: _signatureListKey);
    if (encodedList != null && encodedList.isNotEmpty) {
      try {
        final raw = jsonDecode(encodedList);
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((item) => StoredSignature.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      } catch (_) {
        // Fall through to legacy migration.
      }
    }

    final legacy = await _storage.read(key: _legacySignatureKey);
    if (legacy == null || legacy.isEmpty) return const [];

    try {
      final migrated = [
        StoredSignature(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          bytes: base64Decode(legacy),
          createdAt: DateTime.now(),
        ),
      ];
      await _writeSignatures(migrated);
      await _storage.delete(key: _legacySignatureKey);
      return migrated;
    } on FormatException {
      return const [];
    }
  }

  Future<Uint8List?> loadSignature() async {
    final signatures = await loadSignatures();
    if (signatures.isEmpty) return null;
    return signatures.first.bytes;
  }

  Future<StoredSignature> addSignature(Uint8List bytes) async {
    final signatures = await loadSignatures();
    final signature = StoredSignature(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      bytes: bytes,
      createdAt: DateTime.now(),
    );
    await _writeSignatures([signature, ...signatures]);
    return signature;
  }

  Future<void> saveSignature(Uint8List bytes) async {
    await addSignature(bytes);
  }

  Future<void> removeSignature(String id) async {
    final signatures = await loadSignatures();
    await _writeSignatures(
      signatures.where((signature) => signature.id != id).toList(),
    );
  }

  Future<void> clearSignature() async {
    await _storage.delete(key: _signatureListKey);
    await _storage.delete(key: _legacySignatureKey);
  }

  Future<void> _writeSignatures(List<StoredSignature> signatures) async {
    final encoded = jsonEncode(
      signatures.map((signature) => signature.toJson()).toList(),
    );
    await _storage.write(key: _signatureListKey, value: encoded);
  }
}
