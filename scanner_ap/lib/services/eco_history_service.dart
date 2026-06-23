import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/eco_report.dart';

/// Одна запись истории эко-сканера: миниатюра упаковки + структурированный отчёт.
class EcoHistoryEntry {
  final String id;

  /// Маленький JPEG (base64) для превью в списке истории.
  final String thumbnailBase64;
  final EcoReport report;

  const EcoHistoryEntry({
    required this.id,
    required this.thumbnailBase64,
    required this.report,
  });

  DateTime get createdAt => report.createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'thumb': thumbnailBase64,
        'report': report.toJson(),
      };

  factory EcoHistoryEntry.fromJson(Map<String, dynamic> json) =>
      EcoHistoryEntry(
        id: json['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        thumbnailBase64: json['thumb']?.toString() ?? '',
        report: EcoReport.fromJson(
          Map<String, dynamic>.from(json['report'] as Map),
        ),
      );
}

/// Локальная история премиального эко-сканера (без сервера).
class EcoHistoryService {
  static const _key = 'eco_history_v1';
  static const _maxEntries = 50;
  static const _thumbWidth = 256;

  Future<List<EcoHistoryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = decoded
          .whereType<Map>()
          .map((e) => EcoHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (e) {
      debugPrint('EcoHistoryService: load error $e');
      return const [];
    }
  }

  /// Сохраняет отчёт + миниатюру исходного фото. Возвращает созданную запись.
  Future<EcoHistoryEntry> add(File sourceImage, EcoReport report) async {
    final thumb = await _makeThumbnail(sourceImage);
    final entry = EcoHistoryEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      thumbnailBase64: thumb,
      report: report,
    );
    final all = await loadAll();
    final next = [entry, ...all].take(_maxEntries).toList();
    await _write(next);
    return entry;
  }

  Future<void> remove(String id) async {
    final all = await loadAll();
    await _write(all.where((e) => e.id != id).toList());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> _write(List<EcoHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<String> _makeThumbnail(File source) async {
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return '';
      final resized = decoded.width > _thumbWidth
          ? img.copyResize(decoded, width: _thumbWidth)
          : decoded;
      final jpg = img.encodeJpg(resized, quality: 70);
      return base64Encode(jpg);
    } catch (e) {
      debugPrint('EcoHistoryService: thumbnail error $e');
      return '';
    }
  }
}
