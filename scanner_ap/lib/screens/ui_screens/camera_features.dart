import 'package:flutter/material.dart';

final List<Map<String, dynamic>> cameraFeatures = [
  {
    'name': 'Паспорт',
    'icon': Icons.man,
    'description': 'Выбран режим "Паспорт"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': 'Удостоверение личности',
    'icon': Icons.face,
    'description': 'Выбран режим "Удостоверение личности"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': 'Документ',
    'icon': Icons.book,
    'description': 'Выбран режим "Документ"',
    'isDocument': true,
    'hasTwoPageMode': true
  },
  {
    'name': 'Сканер qr-код',
    'icon': Icons.qr_code,
    'description': 'Мгновенный сканер qr-кода',
    'isDocument': false
  },
  {
    'name': '+10 страниц',
    'icon': Icons.add_circle_outline,
    'description': 'Добавить более 10 страниц',
    'isDocument': true
  },

  {
    'name': 'Перевод',
    'icon': Icons.translate,
    'description': 'Мгновенный перевод текста',
    'isDocument': true
  },
  {
    'name': 'Знак / Подпись',
    'icon': Icons.edit,
    'description': 'Добавление электронной подписи',
    'isDocument': false
  },
  {
    'name': 'Восстановить фото',
    'icon': Icons.restore,
    'description': 'Улучшение качества и восстановление изображений',
    'isDocument': false
  },
  {
    'name': 'Убрать пятна',
    'icon': Icons.cleaning_services,
    'description': 'Автоматическое удаление меток и грязи',
    'isDocument': false
  },
  {
    'name': 'Подсветка текста',
    'icon': Icons.highlight,
    'description': 'Выделение важной информации цветом',
    'isDocument': false
  },
  {
    'name': 'OCR',
    'icon': Icons.text_fields_outlined,
    'description': 'Подсветка текста',
    'isDocument': true,
    'hasTwoPageMode': false
  },
  {
    'name': 'Удалить водяной знак',
    'icon': Icons.delete_forever_outlined,
    'description': 'Удаление водяных знаков',
    'isDocument': false
  },
  {
    'name': 'Ключевые моменты',
    'icon': Icons.vpn_key_outlined,
    'description': 'Выделение ключевых моментов в тексте',
    'isDocument': false
  },
  {
    'name': 'Эко упаковка',
    'icon': Icons.eco,
    'description': 'Оптимизация файла для экологичной печати',
    'isDocument': false
  },
  {
    'name': 'Импорт документов',
    'icon': Icons.file_upload, 
    'isDocument': false, 
  },
];
