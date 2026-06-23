import 'dart:convert';

/// Качественная оценка отдельного материала упаковки.
enum EcoRating { good, medium, bad, unknown }

/// Возможность переработки упаковки в целом.
enum RecyclableStatus { yes, partial, no, unknown }

EcoRating _ratingFrom(Object? value) {
  switch (value?.toString().toLowerCase().trim()) {
    case 'good':
      return EcoRating.good;
    case 'medium':
      return EcoRating.medium;
    case 'bad':
      return EcoRating.bad;
    default:
      return EcoRating.unknown;
  }
}

String _ratingToString(EcoRating r) => r.name;

RecyclableStatus _recyclableFrom(Object? value) {
  switch (value?.toString().toLowerCase().trim()) {
    case 'yes':
      return RecyclableStatus.yes;
    case 'partial':
      return RecyclableStatus.partial;
    case 'no':
      return RecyclableStatus.no;
    default:
      return RecyclableStatus.unknown;
  }
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0.0;
}

String _toStr(Object? value) => value?.toString().trim() ?? '';

List<String> _toStringList(Object? value) {
  if (value is List) {
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

/// Материал упаковки + его эко-рейтинг.
class EcoMaterial {
  final String name;
  final EcoRating rating;

  const EcoMaterial({required this.name, required this.rating});

  factory EcoMaterial.fromJson(Map<String, dynamic> json) => EcoMaterial(
        name: _toStr(json['name']),
        rating: _ratingFrom(json['rating']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'rating': _ratingToString(rating),
      };
}

/// Распознанный значок маркировки переработки (петля Мёбиуса, код пластика…).
class EcoMark {
  final String code;
  final String meaning;
  final bool recyclable;

  const EcoMark({
    required this.code,
    required this.meaning,
    required this.recyclable,
  });

  factory EcoMark.fromJson(Map<String, dynamic> json) => EcoMark(
        code: _toStr(json['code']),
        meaning: _toStr(json['meaning']),
        recyclable: json['recyclable'] == true,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'meaning': meaning,
        'recyclable': recyclable,
      };
}

/// Структурированный результат премиального эко-анализа упаковки.
///
/// Сервер возвращает JSON по фиксированной схеме (см. backend analyzeEco).
/// Парсинг защитный: любое отсутствующее/кривое поле деградирует в пустое
/// значение, чтобы экран не падал на неполном ответе модели.
class EcoReport {
  final double score; // 0..10
  final String verdict;
  final String summary;
  final List<EcoMaterial> materials;
  final RecyclableStatus recyclableStatus;
  final String recyclableNote;
  final String composition;
  final List<EcoMark> marks;
  final List<String> disposal;
  final List<String> tips;

  /// Если модель не вернула валидный JSON — сырой текст для показа как есть.
  final String? rawText;
  final DateTime createdAt;

  const EcoReport({
    required this.score,
    required this.verdict,
    required this.summary,
    required this.materials,
    required this.recyclableStatus,
    required this.recyclableNote,
    required this.composition,
    required this.marks,
    required this.disposal,
    required this.tips,
    required this.createdAt,
    this.rawText,
  });

  bool get isStructured => rawText == null;

  /// Балл, ограниченный 0..10.
  double get clampedScore => score.clamp(0.0, 10.0).toDouble();

  factory EcoReport.fromJson(Map<String, dynamic> json) {
    final recyclable = json['recyclable'];
    final recyclableMap =
        recyclable is Map ? Map<String, dynamic>.from(recyclable) : const {};
    return EcoReport(
      score: _toDouble(json['score']),
      verdict: _toStr(json['verdict']),
      summary: _toStr(json['summary']),
      materials: (json['materials'] is List)
          ? (json['materials'] as List)
              .whereType<Map>()
              .map((e) => EcoMaterial.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      recyclableStatus: _recyclableFrom(recyclableMap['status']),
      recyclableNote: _toStr(recyclableMap['note']),
      composition: _toStr(json['composition']),
      marks: (json['marks'] is List)
          ? (json['marks'] as List)
              .whereType<Map>()
              .map((e) => EcoMark.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      disposal: _toStringList(json['disposal']),
      tips: _toStringList(json['tips']),
      createdAt: DateTime.tryParse(_toStr(json['createdAt'])) ?? DateTime.now(),
      rawText: json['rawText'] as String?,
    );
  }

  /// Парсит JSON-строку из ответа сервера (`result`).
  factory EcoReport.fromServerResult(String result) {
    final decoded = jsonDecode(result);
    if (decoded is Map<String, dynamic>) {
      return EcoReport.fromJson(decoded);
    }
    if (decoded is Map) {
      return EcoReport.fromJson(Map<String, dynamic>.from(decoded));
    }
    throw const FormatException('Eco result is not a JSON object');
  }

  /// Фолбэк, когда модель вернула просто текст (без JSON).
  factory EcoReport.fromRawText(String text) => EcoReport(
        score: 0,
        verdict: '',
        summary: '',
        materials: const [],
        recyclableStatus: RecyclableStatus.unknown,
        recyclableNote: '',
        composition: '',
        marks: const [],
        disposal: const [],
        tips: const [],
        createdAt: DateTime.now(),
        rawText: text.trim(),
      );

  Map<String, dynamic> toJson() => {
        'score': score,
        'verdict': verdict,
        'summary': summary,
        'materials': materials.map((m) => m.toJson()).toList(),
        'recyclable': {
          'status': recyclableStatus.name,
          'note': recyclableNote,
        },
        'composition': composition,
        'marks': marks.map((m) => m.toJson()).toList(),
        'disposal': disposal,
        'tips': tips,
        'createdAt': createdAt.toIso8601String(),
        if (rawText != null) 'rawText': rawText,
      };
}
