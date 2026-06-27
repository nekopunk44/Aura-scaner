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
    'label': 'ID-карта',
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
    'label': 'QR-код',
    'icon': Icons.qr_code,
    'description': 'Мгновенный сканер QR-кода',
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
    'label': 'Подпись',
    'icon': Icons.edit,
    'description': 'Добавление электронной подписи',
    'isDocument': false
  },
  {
    'name': 'Восстановить фото',
    'label': 'Восстановить',
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
    'label': 'Подсветка',
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
    'label': 'Без водзнака',
    'icon': Icons.delete_forever_outlined,
    'description': 'Удаление водяных знаков',
    'isDocument': false
  },
  {
    'name': 'Добавить пароль',
    'label': 'Пароль',
    'icon': Icons.lock_outline,
    'description': 'Пароль на любой файл',
    'isDocument': false
  },
  {
    'name': 'Эко упаковка',
    'label': 'Эко',
    'icon': Icons.eco,
    'description': 'Оптимизация файла для экологичной печати',
    'isDocument': false
  },
];
