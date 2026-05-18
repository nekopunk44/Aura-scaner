import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DocEntry {
  final String localPath;
  final String? remoteId;
  final String name;

  const DocEntry({required this.localPath, this.remoteId, required this.name});

  DocEntry copyWith({String? localPath, String? remoteId, String? name}) => DocEntry(
    localPath: localPath ?? this.localPath,
    remoteId: remoteId ?? this.remoteId,
    name: name ?? this.name,
  );

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'remoteId': remoteId,
    'name': name,
  };

  factory DocEntry.fromJson(Map<String, dynamic> json) => DocEntry(
    localPath: json['localPath'] as String,
    remoteId: json['remoteId'] as String?,
    name: json['name'] as String,
  );
}

class DocumentRegistry {
  static const _key = 'doc_registry_v2';
  static const _legacyKey = 'saved_document_paths';

  static final DocumentRegistry _instance = DocumentRegistry._internal();
  factory DocumentRegistry() => _instance;
  DocumentRegistry._internal();

  List<DocEntry> _entries = [];

  List<DocEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null) {
      // Миграция из старого формата
      final oldPaths = prefs.getStringList(_legacyKey) ?? [];
      _entries = oldPaths.map((p) => DocEntry(
        localPath: p,
        remoteId: null,
        name: nameFromPath(p),
      )).toList();
      await _persist(prefs);
      return;
    }

    final list = jsonDecode(raw) as List<dynamic>;
    _entries = list
        .map((e) => DocEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(DocEntry entry) async {
    _entries.removeWhere((e) => e.localPath == entry.localPath);
    _entries.add(entry);
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> updateRemoteId(String localPath, String remoteId) async {
    final idx = _entries.indexWhere((e) => e.localPath == localPath);
    if (idx == -1) return;
    _entries[idx] = _entries[idx].copyWith(remoteId: remoteId);
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> updateLocalPath(String oldPath, String newPath, String newName) async {
    final idx = _entries.indexWhere((e) => e.localPath == oldPath);
    if (idx == -1) return;
    _entries[idx] = _entries[idx].copyWith(localPath: newPath, name: newName);
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  Future<void> remove(String localPath) async {
    _entries.removeWhere((e) => e.localPath == localPath);
    final prefs = await SharedPreferences.getInstance();
    await _persist(prefs);
  }

  String? getRemoteId(String localPath) {
    try {
      return _entries.firstWhere((e) => e.localPath == localPath).remoteId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(_key, jsonEncode(_entries.map((e) => e.toJson()).toList()));
    // Синхронизируем legacy ключ для совместимости
    await prefs.setStringList(_legacyKey, _entries.map((e) => e.localPath).toList());
  }

  static String nameFromPath(String path) {
    final fileName = path.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot != -1 ? fileName.substring(0, dot) : fileName;
  }
}
