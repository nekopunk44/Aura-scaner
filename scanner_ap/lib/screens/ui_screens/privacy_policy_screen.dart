import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  bool _isEn(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF0F1923) : const Color(0xFFF2F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF4A5568);
    final cardBg = isDark ? const Color(0xFF1E2A3A) : Colors.white;
    const headingColor = Color(0xFF2CA5E0);
    final appBarBg = isDark ? const Color(0xFF141E2B) : Colors.white;
    final l10n = AppLocalizations.of(context);
    final en = _isEn(context);

    final sections = en ? _sectionsEn() : _sectionsRu();

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Text(
          l10n.settingsPrivacyPolicy,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: textColor),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          ...sections.map((s) => _Section(
                number: s.number,
                title: s.title,
                isDark: isDark,
                cardBg: cardBg,
                textColor: textColor,
                subColor: subColor,
                headingColor: headingColor,
                content: s.content,
                items: s.items,
              )),
          const SizedBox(height: 8),
          Center(
            child: Text(
              en ? 'Last updated: June 27, 2026' : 'Последнее обновление: 27 июня 2026 г.',
              style: TextStyle(fontSize: 11, color: subColor),
            ),
          ),
        ],
      ),
    );
  }

  List<_SectionData> _sectionsEn() => [
        _SectionData(
          number: '1',
          title: 'General Provisions',
          content: 'This Privacy Policy describes how the Aura Scanner application (hereinafter — the "App") collects, uses, and protects user data.\n\n'
              'By using the App, you agree to the terms of this Policy. If you do not agree, please discontinue use of the App.',
        ),
        _SectionData(
          number: '2',
          title: 'Data We Collect',
          items: [
            _Item(Icons.camera_alt_outlined, 'Images & Documents',
                'Photos and files you scan or import are processed exclusively on your device and are not sent to third-party servers without your explicit consent.'),
            _Item(Icons.mic_none, 'Voice Notes',
                'Audio recordings created in the Voice Notes section are stored only in the local storage of your device.'),
            _Item(Icons.location_on_outlined, 'Geolocation',
                'Location data is used only when you choose to add a geotag to a document and is not collected in the background.'),
            _Item(Icons.account_circle_outlined, 'Account Data',
                'Upon registration we store your email address and a hashed password. Username and avatar are optional.'),
            _Item(Icons.cloud_outlined, 'Cloud Sync',
                'If you use cloud sync, documents are sent to your own server (the address you specify in Settings). We have no access to your files.'),
          ],
        ),
        _SectionData(
          number: '3',
          title: 'App Permissions',
          items: [
            _Item(Icons.camera_alt_outlined, 'Camera',
                'Used for scanning documents, IDs, passports, QR codes, and the Hot Zone feature.'),
            _Item(Icons.mic_none, 'Microphone',
                'Used exclusively for recording voice notes. Recording starts only when you press the button.'),
            _Item(Icons.photo_library_outlined, 'Photo Library',
                'Used for importing images and saving scanned documents to your device gallery.'),
            _Item(Icons.folder_outlined, 'File Storage',
                'Used for saving PDF files and documents to the app\'s internal storage.'),
          ],
        ),
        _SectionData(
          number: '4',
          title: 'How We Use Data',
          content: 'Collected data is used exclusively for:\n\n'
              '• Providing document scanning and processing features\n'
              '• Text recognition (OCR) via Google ML Kit — processing happens on-device\n'
              '• Text translation via Google ML Kit Translate — works offline\n'
              '• Authentication and sync with your server\n'
              '• Managing your Premium subscription\n\n'
              'We do not sell, rent, or share your personal data with third parties.',
        ),
        _SectionData(
          number: '5',
          title: 'Third-Party Services',
          items: [
            _Item(Icons.android, 'Google ML Kit',
                'Used for OCR, translation, and language detection. Processing is on-device — no data is sent to Google.'),
            _Item(Icons.store, 'Google Play / App Store',
                'Premium subscription payments are processed via Google Play Billing (Android) and Apple StoreKit (iOS). We do not store card details.'),
            _Item(Icons.login, 'OAuth Login',
                'When signing in via Telegram or Google we receive only a basic profile (name, email, ID). Third-party passwords are never accessible to us.'),
          ],
        ),
        _SectionData(
          number: '6',
          title: 'Data Storage & Security',
          content: 'All documents and files are stored in the app\'s protected internal storage, accessible only to the app itself (Android sandbox / iOS container).\n\n'
              'Passwords are stored as hashes. Sensitive account data is transmitted over encrypted HTTPS connections.\n\n'
              'You can delete all app data by uninstalling the app. Data on your server can be removed via the Cloud section or directly on the server.',
        ),
        _SectionData(
          number: '7',
          title: 'Children\'s Data',
          content: 'The App is not intended for children under 13. We do not knowingly collect data from minors. If you believe a child has provided us with personal data, please contact us for its deletion.',
        ),
        _SectionData(
          number: '8',
          title: 'Your Rights',
          content: 'You have the right to:\n\n'
              '• Request information about data we hold\n'
              '• Request correction or deletion of your data\n'
              '• Withdraw consent to data processing\n'
              '• Export your documents\n\n'
              'To exercise your rights, contact us at the address below.',
        ),
        _SectionData(
          number: '9',
          title: 'Policy Changes',
          content: 'We reserve the right to update this Policy. Users will be notified of material changes via an app update or push notification. The date of the last update is shown at the bottom of this document.',
        ),
        _SectionData(
          number: '10',
          title: 'Contact Information',
          content: 'For privacy-related questions, please contact:',
          items: [
            _Item(Icons.email_outlined, 'momentumx010@gmail.com',
                'We will respond within 5 business days'),
          ],
        ),
      ];

  List<_SectionData> _sectionsRu() => [
        _SectionData(
          number: '1',
          title: 'Общие положения',
          content: 'Настоящая Политика конфиденциальности описывает, каким образом приложение «Aura Scanner» (далее — «Приложение») собирает, использует и защищает данные пользователей.\n\n'
              'Используя Приложение, вы соглашаетесь с условиями данной Политики. Если вы не согласны с её условиями — пожалуйста, прекратите использование Приложения.',
        ),
        _SectionData(
          number: '2',
          title: 'Какие данные мы собираем',
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
        _SectionData(
          number: '3',
          title: 'Разрешения приложения',
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
        _SectionData(
          number: '4',
          title: 'Как мы используем данные',
          content: 'Собранные данные используются исключительно для:\n\n'
              '• Обеспечения работы функций сканирования и обработки документов\n'
              '• Распознавания текста (OCR) с помощью Google ML Kit — обработка происходит на устройстве\n'
              '• Перевода текста с помощью Google ML Kit Translate — работает офлайн\n'
              '• Авторизации и синхронизации с вашим сервером\n'
              '• Оформления и управления подпиской Premium\n\n'
              'Мы не продаём, не сдаём в аренду и не передаём ваши персональные данные третьим лицам.',
        ),
        _SectionData(
          number: '5',
          title: 'Сторонние сервисы',
          items: [
            _Item(Icons.android, 'Google ML Kit',
                'Используется для OCR (распознавание текста), перевода и определения языка. Обработка производится на устройстве без передачи данных в Google.'),
            _Item(Icons.store, 'Google Play / App Store',
                'Платежи за Premium-подписку обрабатываются через Google Play Billing (Android) и Apple StoreKit (iOS). Мы не храним данные банковских карт.'),
            _Item(Icons.login, 'OAuth-авторизация',
                'При входе через Telegram или Google мы получаем только базовый профиль (имя, email, ID). Пароли сторонних сервисов нам недоступны.'),
          ],
        ),
        _SectionData(
          number: '6',
          title: 'Хранение и защита данных',
          content: 'Все документы и файлы хранятся в защищённом внутреннем хранилище приложения, доступном только самому приложению (Android sandbox / iOS container).\n\n'
              'Пароли хранятся в хэшированном виде. Чувствительные данные аккаунта передаются по зашифрованному HTTPS-соединению.\n\n'
              'Вы можете удалить все данные приложения, удалив его с устройства. Данные на вашем сервере удаляются через раздел «Облако» или напрямую на сервере.',
        ),
        _SectionData(
          number: '7',
          title: 'Данные несовершеннолетних',
          content: 'Приложение не предназначено для детей младше 13 лет. Мы сознательно не собираем данные лиц младше указанного возраста. Если вам стало известно, что ребёнок предоставил нам персональные данные — свяжитесь с нами для их удаления.',
        ),
        _SectionData(
          number: '8',
          title: 'Ваши права',
          content: 'Вы вправе:\n\n'
              '• Запросить информацию о хранящихся данных\n'
              '• Потребовать исправления или удаления ваших данных\n'
              '• Отозвать согласие на обработку данных\n'
              '• Экспортировать свои документы\n\n'
              'Для реализации прав обратитесь по контактному адресу, указанному ниже.',
        ),
        _SectionData(
          number: '9',
          title: 'Изменения политики',
          content: 'Мы оставляем за собой право изменять настоящую Политику. При внесении существенных изменений пользователи будут уведомлены через обновление приложения или push-уведомление. Дата последнего обновления указана в нижней части документа.',
        ),
        _SectionData(
          number: '10',
          title: 'Контактная информация',
          content: 'По вопросам, связанным с конфиденциальностью, обращайтесь:',
          items: [
            _Item(Icons.email_outlined, 'momentumx010@gmail.com',
                'Ответим в течение 5 рабочих дней'),
          ],
        ),
      ];
}

class _SectionData {
  final String number;
  final String title;
  final String? content;
  final List<_Item>? items;
  const _SectionData({required this.number, required this.title, this.content, this.items});
}

class _Item {
  final IconData icon;
  final String title;
  final String text;
  const _Item(this.icon, this.title, this.text);
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

  Widget _buildContent(String text) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    bool afterBullet = false;

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(SizedBox(height: afterBullet ? 4 : 8));
        afterBullet = false;
        continue;
      }
      if (line.trimLeft().startsWith('•')) {
        final bulletText = line.trimLeft().substring(1).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: headingColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(bulletText,
                    style: TextStyle(fontSize: 13, color: subColor, height: 1.55)),
              ),
            ],
          ),
        ));
        afterBullet = true;
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(line, style: TextStyle(fontSize: 13, color: subColor, height: 1.6)),
        ));
        afterBullet = false;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }

  @override
  Widget build(BuildContext context) {
    final divColor =
        isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: headingColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(number,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: headingColor)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: divColor),
          if (content != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: _buildContent(content!),
            ),
          if (items != null)
            ...items!.asMap().entries.map((e) => Column(
                  children: [
                    if (content != null || e.key > 0) Divider(height: 1, color: divColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: headingColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(e.value.icon, size: 18, color: headingColor),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.value.title,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textColor)),
                                if (e.value.text.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(e.value.text,
                                      style: TextStyle(
                                          fontSize: 12, color: subColor, height: 1.4)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
        ],
      ),
    );
  }
}
