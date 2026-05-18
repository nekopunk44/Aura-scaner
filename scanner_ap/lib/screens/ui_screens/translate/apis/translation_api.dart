import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:flutter/foundation.dart';

/// Основной сервис перевода текста с изображений.
///
/// Полный pipeline перевода (всё работает офлайн через Google ML Kit):
///
/// 1. **Анализ текста** — определяет соотношение кириллицы/латиницы
/// 2. **Детекция транслита** — ищет паттерны "sh", "ch", "zh", "yu" и т.д.
/// 3. **Конвертация транслита** — "privet" → "привет"
/// 4. **Очистка OCR-артефактов** — исправляет "rn"→"m", "cl"→"d", "vv"→"w"
/// 5. **Определение языка** — через LanguageIdentifier (порог уверенности 0.4)
/// 6. **Перевод** — OnDeviceTranslator → English
/// 7. **Валидация** — проверяет что перевод не пустой и не совпадает с оригиналом
/// 8. **Форматирование** — заглавная буква + точка в конце
///
/// Поддерживаемые языки: ru, en, es, fr, de, it, pt, ar, zh, ja, ko, pl, tr,
/// nl, sv, da, fi, no, cs, sk, hu, ro, bg, el, he, hi, th, vi.
///
/// Все методы статические — создавать экземпляр не нужно.
class TranslationApi {
  static Future<String?> translateText(String recognizedText) async {
    try {
      debugPrint('=' * 60);
      debugPrint('НАЧАЛО ПЕРЕВОДА');
      debugPrint('Длина текста: ${recognizedText.length} символов');

      if (recognizedText.isEmpty) {
        debugPrint('Текст пустой');
        return null;
      }

      debugPrint('\n=== АНАЛИЗ ТЕКСТА ===');
      final textAnalysis = _analyzeText(recognizedText);
      debugPrint('Тип текста: ${textAnalysis['type']}');
      debugPrint('Кириллица: ${textAnalysis['cyrillic_count']}');
      debugPrint('Латиница: ${textAnalysis['latin_count']}');
      debugPrint('Процент кириллицы: ${textAnalysis['cyrillic_percent']}%');

      String processedText = recognizedText;

      if (textAnalysis['is_translit'] == true) {
        debugPrint('\n=== КОНВЕРТАЦИЯ ТРАНСЛИТА ===');
        processedText = _convertTranslitToCyrillic(processedText);
        debugPrint('После конвертации: ${_getPreview(processedText)}');

        final newAnalysis = _analyzeText(processedText);
        if (newAnalysis['cyrillic_percent'] > 50) {
          debugPrint('Транслит успешно конвертирован в кириллицу');
        }
      }

      debugPrint('\n=== ОЧИСТКА ТЕКСТА ===');
      final cleanedText = _cleanText(processedText);
      debugPrint('После очистки: ${_getPreview(cleanedText)}');

      if (cleanedText.trim().isEmpty) {
        debugPrint('Текст пуст после очистки');
        return null;
      }

      if (_isAlreadyEnglish(cleanedText)) {
        debugPrint('\nТекст уже на английском, возвращаем очищенный вариант');
        return _formatOutput(cleanedText, isEnglish: true);
      }

      debugPrint('\n=== ОПРЕДЕЛЕНИЕ ЯЗЫКА ===');
      final sourceLanguage = await _determineSourceLanguage(cleanedText);
      debugPrint('Определенный язык: $sourceLanguage');

      if (sourceLanguage == 'en' || sourceLanguage == 'und' || sourceLanguage.isEmpty) {
        debugPrint('Язык английский или не определен, перевод не требуется');
        return _formatOutput(cleanedText, isEnglish: true);
      }

   
      debugPrint('\n=== ВЫПОЛНЕНИЕ ПЕРЕВОДА ===');
      debugPrint('Исходный текст ($sourceLanguage): ${_getPreview(cleanedText)}');

      final translatedText = await _performTranslation(cleanedText, sourceLanguage);

      if (translatedText == null) {
        debugPrint('Перевод не удался, возвращаем оригинал');
        return _formatOutput(cleanedText);
      }

      debugPrint('Переведенный текст: ${_getPreview(translatedText)}');

      if (!_isValidTranslation(cleanedText, translatedText, sourceLanguage)) {
        debugPrint('Перевод признан некачественным, возвращаем оригинал');
        return _formatOutput(cleanedText);
      }

      final formattedResult = _formatOutput(translatedText);
      debugPrint('\n=== РЕЗУЛЬТАТ ===');
      debugPrint('Итоговый текст: $formattedResult');
      debugPrint('=' * 60);

      return formattedResult;

    } catch (e, stackTrace) {
      debugPrint('\n=== ОШИБКА ПЕРЕВОДА ===');
      debugPrint('Ошибка: $e');
      debugPrint('Стек: $stackTrace');
      return null;
    }
  }

  static Map<String, dynamic> _analyzeText(String text) {
    final cyrillicCount = RegExp(r'[а-яА-ЯёЁ]').allMatches(text).length;
    final latinCount = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final digitCount = RegExp(r'[0-9]').allMatches(text).length;
    final symbolCount = text.length - cyrillicCount - latinCount - digitCount;

    final totalLetters = cyrillicCount + latinCount;
    final cyrillicPercent = totalLetters > 0 ? (cyrillicCount / totalLetters * 100).round() : 0;
    final latinPercent = totalLetters > 0 ? (latinCount / totalLetters * 100).round() : 0;

    String type = 'unknown';
    bool isTranslit = false;

    if (cyrillicPercent > 70) {
      type = 'cyrillic';
    } else if (latinPercent > 70) {
      isTranslit = _detectTranslit(text);
      type = isTranslit ? 'translit' : 'latin';
    } else if (cyrillicCount > 0 && latinCount > 0) {
      type = 'mixed';
      isTranslit = _detectTranslit(text);
    }

    return {
      'type': type,
      'is_translit': isTranslit,
      'cyrillic_count': cyrillicCount,
      'latin_count': latinCount,
      'digit_count': digitCount,
      'symbol_count': symbolCount,
      'cyrillic_percent': cyrillicPercent,
      'latin_percent': latinPercent,
      'total_letters': totalLetters,
    };
  }

  static bool _detectTranslit(String text) {
    if (text.length < 3) return false;

    final translitPatterns = [
      RegExp(r'\b(sh|ch|zh|yu|ya|yo|kh|shch|ts|sch)([^a-zA-Z]|$)', caseSensitive: false),
      RegExp(r'[a-z]*[aeiouy]{3,}[a-z]*', caseSensitive: false), // несколько гласных подряд
      RegExp(r'\b([a-z]+[0-9]+|[0-9]+[a-z]+)\b', caseSensitive: false), // буквы+цифры
    ];

    int translitScore = 0;

    for (final pattern in translitPatterns) {
      final matches = pattern.allMatches(text);
      if (matches.length > text.length / 20) { 
        translitScore += 2;
      }
    }

    final englishWords = ['the', 'and', 'you', 'that', 'have', 'for', 'not', 'with', 'this', 'but'];
    int englishWordCount = 0;

    final words = text.toLowerCase().split(RegExp(r'[^\w]'));
    for (final word in words) {
      if (word.length > 2 && englishWords.contains(word)) {
        englishWordCount++;
      }
    }

    return translitScore > 1 && englishWordCount < words.length / 10;
  }

  static String _convertTranslitToCyrillic(String text) {
    final Map<String, String> translitMap = {
      'shch': 'щ', 'SHCH': 'Щ', 'Shch': 'Щ',
      'sch': 'щ', 'SCH': 'Щ', 'Sch': 'Щ',
      'ch': 'ч', 'CH': 'Ч', 'Ch': 'Ч',
      'sh': 'ш', 'SH': 'Ш', 'Sh': 'Ш',
      'zh': 'ж', 'ZH': 'Ж', 'Zh': 'Ж',
      'yu': 'ю', 'YU': 'Ю', 'Yu': 'Ю',
      'ya': 'я', 'YA': 'Я', 'Ya': 'Я',
      'yo': 'ё', 'YO': 'Ё', 'Yo': 'Ё',
      'kh': 'х', 'KH': 'Х', 'Kh': 'Х',
      'ts': 'ц', 'TS': 'Ц', 'Ts': 'Ц',
      'ju': 'ю', 'JU': 'Ю', 'Ju': 'Ю', 
      'ja': 'я', 'JA': 'Я', 'Ja': 'Я',  


      'a': 'а', 'A': 'А',
      'b': 'б', 'B': 'Б',
      'v': 'в', 'V': 'В',
      'g': 'г', 'G': 'Г',
      'd': 'д', 'D': 'Д',
      'e': 'е', 'E': 'Е',
      'z': 'з', 'Z': 'З',
      'i': 'и', 'I': 'И',
      'j': 'й', 'J': 'Й',
      'k': 'к', 'K': 'К',
      'l': 'л', 'L': 'Л',
      'm': 'м', 'M': 'М',
      'n': 'н', 'N': 'Н',
      'o': 'о', 'O': 'О',
      'p': 'п', 'P': 'П',
      'r': 'р', 'R': 'Р',
      's': 'с', 'S': 'С',
      't': 'т', 'T': 'Т',
      'u': 'у', 'U': 'У',
      'f': 'ф', 'F': 'Ф',
      'h': 'х', 'H': 'Х',
      'c': 'ц', 'C': 'Ц',
      'y': 'ы', 'Y': 'Ы',
      "'": 'ь', '"': 'ъ', '`': 'ь', 'ʹ': 'ь',
      'x': 'кс', 'X': 'КС', // x обычно не используется в русском
      'w': 'в', 'W': 'В',   // w иногда заменяет в
      'q': 'к', 'Q': 'К',   // q иногда заменяет к
    };

    String result = text;

    final multiCharPatterns = translitMap.keys.where((key) => key.length > 1).toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // Сначала самые длинные

    for (final pattern in multiCharPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      result = result.replaceAllMapped(regex, (match) {
        final matched = match.group(0)!;
        final replacement = translitMap[pattern] ?? matched;

        if (matched.toUpperCase() == matched) {
          return replacement.toUpperCase();
        } else if (matched[0].toUpperCase() == matched[0]) {
          return replacement[0].toUpperCase() + replacement.substring(1);
        }
        return replacement;
      });
    }

    for (final entry in translitMap.entries.where((e) => e.key.length == 1)) {
      result = result.replaceAll(entry.key, entry.value);
    }

    result = result.replaceAll(RegExp(r'й[оo]', caseSensitive: false), 'ё');
    result = result.replaceAll(RegExp(r'Й[ОO]'), 'Ё');
    result = result.replaceAll(RegExp(r'ий\b'), 'ый');
    result = result.replaceAll(RegExp(r'Ий\b'), 'Ый');
    result = result.replaceAll(RegExp(r'ия\b'), 'ия'); // сохраняем окончания

    return result;
  }

  static String _cleanText(String text) {
    if (text.isEmpty) return '';

    String cleaned = text;

    // 1. Заменяем похожие символы
    cleaned = cleaned
        .replaceAll('|', 'I')  // Вертикальная черта
        .replaceAll('1', 'l')  // Цифра 1 на букву l (в контексте)
        .replaceAll('0', 'O')  // Ноль на букву O
        .replaceAll('5', 'S')  // Пятерка на S
        .replaceAll('8', 'B'); // Восьмерка на B

    // 2. Убираем непечатаемые символы
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ');

    // 3. Убираем лишние пробелы и символы
    cleaned = cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s+|\s+$'), '')
        .replaceAll(RegExp(r'\s([.,!?;:])'), r'$1'); // пробелы перед знаками препинания

    final ocrCorrections = {
      'rn': 'm', 'cl': 'd', 'vv': 'w', 'ii': 'n',
      'IJ': 'H', '|I': 'H', '1I': 'H',
    };

    for (final correction in ocrCorrections.entries) {
      cleaned = cleaned.replaceAll(correction.key, correction.value);
    }

    return cleaned;
  }

  /// Проверка, не является ли текст уже английским
  static bool _isAlreadyEnglish(String text) {
    if (text.length < 3) return false;

    final words = text.toLowerCase().split(RegExp(r'[^\w]+'));
    if (words.isEmpty) return false;

    // Распространенные английские слова
    final commonEnglishWords = {
      'the', 'and', 'you', 'that', 'have', 'for', 'not', 'with', 'this', 'but',
      'from', 'they', 'say', 'her', 'she', 'will', 'one', 'all', 'would', 'there',
      'their', 'what', 'out', 'about', 'who', 'get', 'which', 'when', 'make',
      'can', 'like', 'time', 'just', 'him', 'know', 'take', 'person', 'into',
      'year', 'your', 'good', 'some', 'could', 'them', 'see', 'other', 'than',
      'then', 'now', 'look', 'only', 'come', 'its', 'over', 'think', 'also',
      'back', 'after', 'use', 'two', 'how', 'our', 'work', 'first', 'well',
      'way', 'even', 'new', 'want', 'because', 'any', 'these', 'give', 'day',
      'most', 'us'
    };

    int englishWordCount = 0;
    int totalValidWords = 0;

    for (final word in words) {
      if (word.length > 2) { 
        totalValidWords++;
        if (commonEnglishWords.contains(word)) {
          englishWordCount++;
        }
      }
    }

    if (totalValidWords == 0) return false;

    final englishRatio = englishWordCount / totalValidWords;
    debugPrint('Английских слов: $englishWordCount из $totalValidWords ($englishRatio)');

    return englishRatio > 0.3; 
  }

  static Future<String> _determineSourceLanguage(String text) async {
    try {
      if (text.length < 3) return 'und';

      final langIdentifier = LanguageIdentifier(confidenceThreshold: 0.1);
      final possibleLanguages = await langIdentifier.identifyPossibleLanguages(text);
      await langIdentifier.close();

      if (possibleLanguages.isEmpty) return 'und';

      possibleLanguages.sort((a, b) => b.confidence.compareTo(a.confidence));


      debugPrint('Возможные языки:');
      for (int i = 0; i < min(3, possibleLanguages.length); i++) {
        final lang = possibleLanguages[i];
        debugPrint('  ${lang.languageTag}: ${(lang.confidence * 100).toStringAsFixed(1)}%');
      }

      final bestLang = possibleLanguages.first;

      if (bestLang.confidence < 0.4) {
        debugPrint('Низкая уверенность (${(bestLang.confidence * 100).toStringAsFixed(1)}%), анализируем вручную');
        return _manualLanguageDetection(text);
      }

      return bestLang.languageTag.split('-')[0]; 

    } catch (e) {
      debugPrint('Ошибка определения языка: $e');
      return _manualLanguageDetection(text);
    }
  }

  static String _manualLanguageDetection(String text) {
    final cyrillicCount = RegExp(r'[а-яА-ЯёЁ]').allMatches(text).length;
    final latinCount = RegExp(r'[a-zA-Z]').allMatches(text).length;

    if (cyrillicCount > latinCount * 2) {
      return 'ru';
    } else if (latinCount > cyrillicCount * 2) {
      return 'en';
    } else if (cyrillicCount > 0) {
      return 'ru'; 
    }

    return 'en';
  }

  
  static Future<String?> _performTranslation(String text, String sourceLangCode) async {
    try {
      final sourceLanguage = _mapLanguageCode(sourceLangCode);
      if (sourceLanguage == null) {
        debugPrint('Язык $sourceLangCode не поддерживается для перевода');
        return null;
      }

      debugPrint('Создаем переводчик: $sourceLanguage -> английский');

      final translator = OnDeviceTranslator(
        sourceLanguage: sourceLanguage,
        targetLanguage: TranslateLanguage.english,
      );

      final startTime = DateTime.now();
      final translatedText = await translator.translateText(text);
      final endTime = DateTime.now();

      await translator.close();

      final duration = endTime.difference(startTime);
      debugPrint('Перевод выполнен за ${duration.inMilliseconds}ms');

      return translatedText;

    } catch (e, stackTrace) {
      debugPrint('Ошибка при переводе: $e');
      debugPrint('Стек: $stackTrace');
      return null;
    }
  }

  /// Проверка валидности перевода
  static bool _isValidTranslation(String original, String translated, String sourceLang) {
    if (translated.trim().isEmpty) {
      debugPrint('Перевод пустой');
      return false;
    }

    if (translated.toLowerCase() == original.toLowerCase()) {
      debugPrint('Перевод совпадает с оригиналом');
      return false;
    }

    if (translated.length < original.length / 3 && original.length > 10) {
      debugPrint('Перевод слишком короткий');
      return false;
    }

    final letterCount = RegExp(r'[a-zA-Z]').allMatches(translated).length;
    if (letterCount < translated.length * 0.3 && translated.length > 5) {
      debugPrint('Слишком мало букв в переводе');
      return false;
    }


    final garbagePatterns = [
      RegExp(r'^[^a-zA-Zа-яА-Я]*$'), // Только не-буквы
      RegExp(r'[0-9]{5,}'), // Много цифр подряд
      RegExp(r'[\w\s]{1,3}$'), // Слишком короткий результат
    ];

    for (final pattern in garbagePatterns) {
      if (pattern.hasMatch(translated)) {
        debugPrint('Перевод содержит мусорный паттерн');
        return false;
      }
    }

    return true;
  }

  static String _formatOutput(String text, {bool isEnglish = false}) {
    if (text.isEmpty) return '';

    String formatted = text.trim();


    formatted = formatted.replaceAll(RegExp(r'\s+'), ' ');

    if (formatted.length > 1) {
      final firstChar = formatted[0];
      if (RegExp(r'[a-zA-Zа-яА-Я]').hasMatch(firstChar)) {
        formatted = firstChar.toUpperCase() + formatted.substring(1);
      }
    }

    if (formatted.isNotEmpty &&
        !formatted.endsWith('.') &&
        !formatted.endsWith('!') &&
        !formatted.endsWith('?') &&
        !formatted.endsWith('...') &&
        formatted.length > 10) {
      formatted += '.';
    }

    return formatted;
  }

  static String _getPreview(String text, {int maxLength = 50}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  static TranslateLanguage? _mapLanguageCode(String code) {
    final baseCode = code.toLowerCase().split('-')[0];

    switch (baseCode) {
      case 'ru': case 'be': case 'uk':
      return TranslateLanguage.russian;
      case 'en': return TranslateLanguage.english;
      case 'es': return TranslateLanguage.spanish;
      case 'fr': return TranslateLanguage.french;
      case 'de': return TranslateLanguage.german;
      case 'it': return TranslateLanguage.italian;
      case 'pt': return TranslateLanguage.portuguese;
      case 'ar': return TranslateLanguage.arabic;
      case 'zh': return TranslateLanguage.chinese;
      case 'ja': return TranslateLanguage.japanese;
      case 'ko': return TranslateLanguage.korean;
      case 'pl': return TranslateLanguage.polish;
      case 'tr': return TranslateLanguage.turkish;
      case 'nl': return TranslateLanguage.dutch;
      case 'sv': return TranslateLanguage.swedish;
      case 'da': return TranslateLanguage.danish;
      case 'fi': return TranslateLanguage.finnish;
      case 'no': return TranslateLanguage.norwegian;
      case 'cs': return TranslateLanguage.czech;
      case 'sk': return TranslateLanguage.slovak;
      case 'hu': return TranslateLanguage.hungarian;
      case 'ro': return TranslateLanguage.romanian;
      case 'bg': return TranslateLanguage.bulgarian;
      case 'el': return TranslateLanguage.greek;
      case 'he': return TranslateLanguage.hebrew;
      case 'hi': return TranslateLanguage.hindi;
      case 'th': return TranslateLanguage.thai;
      case 'vi': return TranslateLanguage.vietnamese;
      default:
        debugPrint('Неизвестный код языка: $code');
        return null;
    }
  }

  static int min(int a, int b) => a < b ? a : b;
}