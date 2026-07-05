import 'package:flutter/material.dart';

/// Внутренние идентификаторы режимов камеры.
///
/// Исторически режимы адресуются русскими строками (они же ключи в
/// [cameraFeatures] и в логике camera.dart). Значения менять нельзя —
/// они могут храниться в состоянии/настройках; но все обращения идут
/// через эти константы, чтобы опечатка ломала компиляцию, а не логику
/// в рантайме.
abstract final class Feat {
  static const passport = 'Паспорт';
  static const idCard = 'Удостоверение личности';
  static const document = 'Документ';
  static const qrScanner = 'Сканер qr-код';
  static const plus10Pages = '+10 страниц';
  static const translate = 'Перевод';
  static const signature = 'Знак / Подпись';
  static const restorePhoto = 'Восстановить фото';
  static const removeSpots = 'Убрать пятна';
  static const highlight = 'Подсветка текста';
  static const ocr = 'OCR';
  static const removeWatermark = 'Удалить водяной знак';
  static const addPassword = 'Добавить пароль';
  static const eco = 'Эко упаковка';
  static const importDocs = 'Импорт документов';
}

final List<Map<String, dynamic>> cameraFeatures = [
  {
    'name': Feat.passport,
    'icon': Icons.man,
    'description': 'Выбран режим "Паспорт"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': Feat.idCard,
    'label': 'ID-карта',
    'icon': Icons.face,
    'description': 'Выбран режим "Удостоверение личности"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': Feat.document,
    'icon': Icons.book,
    'description': 'Выбран режим "Документ"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': Feat.qrScanner,
    'label': 'QR-код',
    'icon': Icons.qr_code,
    'description': 'Мгновенный сканер QR-кода',
    'isDocument': false
  },
  {
    'name': Feat.plus10Pages,
    'icon': Icons.add_circle_outline,
    'description': 'Добавить более 10 страниц',
    'isDocument': true
  },

  {
    'name': Feat.translate,
    'icon': Icons.translate,
    'description': 'Мгновенный перевод текста',
    'isDocument': true
  },
  {
    'name': Feat.signature,
    'label': 'Подпись',
    'icon': Icons.edit,
    'description': 'Добавление электронной подписи',
    'isDocument': false
  },
  {
    'name': Feat.restorePhoto,
    'label': 'Восстановить',
    'icon': Icons.restore,
    'description': 'Улучшение качества и восстановление изображений',
    'isDocument': false
  },
  {
    'name': Feat.removeSpots,
    'icon': Icons.cleaning_services,
    'description': 'Автоматическое удаление меток и грязи',
    'isDocument': false
  },
  {
    'name': Feat.highlight,
    'label': 'Подсветка',
    'icon': Icons.highlight,
    'description': 'Выделение важной информации цветом',
    'isDocument': false
  },
  {
    'name': Feat.ocr,
    'icon': Icons.text_fields_outlined,
    'description': 'Подсветка текста',
    'isDocument': true,
    'hasTwoPageMode': false
  },
  {
    'name': Feat.removeWatermark,
    'label': 'Без водзнака',
    'icon': Icons.delete_forever_outlined,
    'description': 'Удаление водяных знаков',
    'isDocument': false
  },
  {
    'name': Feat.addPassword,
    'label': 'Пароль',
    'icon': Icons.lock_outline,
    'description': 'Пароль на любой файл',
    'isDocument': false
  },
  {
    'name': Feat.eco,
    'label': 'Эко',
    'icon': Icons.eco,
    'description': 'Оптимизация файла для экологичной печати',
    'isDocument': false
  },
];
