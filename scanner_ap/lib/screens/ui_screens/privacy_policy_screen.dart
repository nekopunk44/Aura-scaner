import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF4A5568);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    final headingColor = const Color(0xFF2CA5E0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text('Политика конфиденциальности',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16)),
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _HeaderCard(isDark: isDark, cardBg: cardBg, textColor: textColor, subColor: subColor),
          const SizedBox(height: 16),
          _Section(
            number: '1',
            title: 'Общие положения',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Настоящая Политика конфиденциальности описывает, каким образом приложение «Aura Scanner» (далее — «Приложение») собирает, использует и защищает данные пользователей.\n\n'
                'Используя Приложение, вы соглашаетесь с условиями данной Политики. Если вы не согласны с её условиями — пожалуйста, прекратите использование Приложения.',
          ),
          _Section(
            number: '2',
            title: 'Какие данные мы собираем',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            items: [
              _Item(Icons.camera_alt_outlined, 'Изображения и документы',
                  'Фотографии и файлы, которые вы сканируете или импортируете, обрабатываются исключительно на вашем устройстве и не передаются на сторонние серверы без вашего явного согласия.'),
              _Item(Icons.mic_none, 'Голосовые заметки',
                  'Аудиозаписи, созданные в разделе «Голосовые заметки», хранятся только в локальном хранилище устройства.'),
              _Item(Icons.location_on_outlined, 'Геолокация',
                  'Данные о местоположении используются только при добавлении геометки к документу по вашему запросу и не сохраняются в фоновом режиме.'),
              _Item(Icons.account_circle_outlined, 'Данные аккаунта',
                  'При регистрации мы сохраняем адрес электронной почты и хэш пароля. Имя пользователя и аватар — опционально.'),
              _Item(Icons.cloud_outlined, 'Облачная синхронизация',
                  'Если вы используете облачную синхронизацию, документы передаются на ваш собственный сервер (адрес которого вы указываете самостоятельно в настройках). Мы не имеем доступа к вашим файлам.'),
            ],
          ),
          _Section(
            number: '3',
            title: 'Разрешения приложения',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            items: [
              _Item(Icons.camera_alt_outlined, 'Камера',
                  'Используется для сканирования документов, удостоверений, паспортов, QR-кодов и работы функции «Горячая зона».'),
              _Item(Icons.mic_none, 'Микрофон',
                  'Используется исключительно для записи голосовых заметок в функции «Голосовая заметка». Запись начинается только по нажатию кнопки.'),
              _Item(Icons.photo_library_outlined, 'Фотогалерея',
                  'Используется для импорта изображений и сохранения отсканированных документов в галерею устройства.'),
              _Item(Icons.folder_outlined, 'Файловое хранилище',
                  'Используется для сохранения PDF-файлов и документов во внутреннем хранилище приложения.'),
            ],
          ),
          _Section(
            number: '4',
            title: 'Как мы используем данные',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Собранные данные используются исключительно для:\n\n'
                '• Обеспечения работы функций сканирования и обработки документов\n'
                '• Распознавания текста (OCR) с помощью Google ML Kit — обработка происходит на устройстве\n'
                '• Перевода текста с помощью Google ML Kit Translate — работает офлайн\n'
                '• Авторизации и синхронизации с вашим сервером\n'
                '• Оформления и управления подпиской Premium\n\n'
                'Мы не продаём, не сдаём в аренду и не передаём ваши персональные данные третьим лицам.',
          ),
          _Section(
            number: '5',
            title: 'Сторонние сервисы',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            items: [
              _Item(Icons.android, 'Google ML Kit',
                  'Используется для OCR (распознавание текста), перевода и определения языка. Обработка производится на устройстве без передачи данных в Google.'),
              _Item(Icons.store, 'Google Play / App Store',
                  'Платежи за Premium-подписку обрабатываются через Google Play Billing (Android) и Apple StoreKit (iOS). Мы не храним данные банковских карт.'),
              _Item(Icons.login, 'OAuth-авторизация',
                  'При входе через ВКонтакте или Google мы получаем только базовый профиль (имя, email, ID). Пароли сторонних сервисов нам недоступны.'),
            ],
          ),
          _Section(
            number: '6',
            title: 'Хранение и защита данных',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Все документы и файлы хранятся в защищённом внутреннем хранилище приложения, доступном только самому приложению (Android sandbox / iOS container).\n\n'
                'Пароли хранятся в хэшированном виде. Чувствительные данные аккаунта передаются по зашифрованному HTTPS-соединению.\n\n'
                'Вы можете удалить все данные приложения, удалив его с устройства. Данные на вашем сервере удаляются через раздел «Облако» или напрямую на сервере.',
          ),
          _Section(
            number: '7',
            title: 'Данные несовершеннолетних',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Приложение не предназначено для детей младше 13 лет. Мы сознательно не собираем данные лиц младше указанного возраста. Если вам стало известно, что ребёнок предоставил нам персональные данные — свяжитесь с нами для их удаления.',
          ),
          _Section(
            number: '8',
            title: 'Ваши права',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Вы вправе:\n\n'
                '• Запросить информацию о хранящихся данных\n'
                '• Потребовать исправления или удаления ваших данных\n'
                '• Отозвать согласие на обработку данных\n'
                '• Экспортировать свои документы\n\n'
                'Для реализации прав обратитесь по контактному адресу, указанному ниже.',
          ),
          _Section(
            number: '9',
            title: 'Изменения политики',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'Мы оставляем за собой право изменять настоящую Политику. При внесении существенных изменений пользователи будут уведомлены через обновление приложения или push-уведомление. Дата последнего обновления указана в нижней части документа.',
          ),
          _Section(
            number: '10',
            title: 'Контактная информация',
            isDark: isDark,
            cardBg: cardBg,
            textColor: textColor,
            subColor: subColor,
            headingColor: headingColor,
            content: 'По вопросам, связанным с конфиденциальностью, обращайтесь:\n\n'
                '📧 oleghyt4@gmail.com\n\n'
                'Мы постараемся ответить в течение 5 рабочих дней.',
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Последнее обновление: 20 мая 2025 г.',
              style: TextStyle(fontSize: 11, color: subColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final bool isDark;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  const _HeaderCard({required this.isDark, required this.cardBg, required this.textColor, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2CA5E0), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aura Scanner',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                SizedBox(height: 3),
                Text('Политика конфиденциальности',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String title;
  final String text;
  _Item(this.icon, this.title, this.text);
}

class _Section extends StatelessWidget {
  final String number;
  final String title;
  final bool isDark;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  final Color headingColor;
  final String? content;
  final List<_Item>? items;

  const _Section({
    required this.number,
    required this.title,
    required this.isDark,
    required this.cardBg,
    required this.textColor,
    required this.subColor,
    required this.headingColor,
    this.content,
    this.items,
  });

  @override
  Widget build(BuildContext context) {
    final divColor = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: headingColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(number,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: headingColor)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: divColor),
          if (content != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(content!,
                  style: TextStyle(fontSize: 13, color: subColor, height: 1.6)),
            ),
          if (items != null)
            ...items!.asMap().entries.map((e) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: headingColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(e.value.icon, size: 18, color: headingColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.value.title,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
                            const SizedBox(height: 4),
                            Text(e.value.text,
                                style: TextStyle(fontSize: 12, color: subColor, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (e.key < items!.length - 1)
                  Divider(height: 1, indent: 62, color: divColor),
              ],
            )),
        ],
      ),
    );
  }
}
