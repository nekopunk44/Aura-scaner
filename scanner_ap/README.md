# Aura Scanner

Основной Flutter-клиент проекта `Aura Scanner`.

Приложение предназначено для:

- сканирования документов, паспорта и ID-карты;
- импорта локальных файлов;
- просмотра и базового редактирования документов;
- OCR и перевода текста через камеру;
- PDF-операций;
- локального хранения и облачной синхронизации документов.

## Текущее состояние

По текущему коду в приложении уже есть:

- логин и регистрация;
- экран локальных документов;
- экран облачных документов;
- импорт `pdf`, `doc`, `docx`, `txt`, `jpg`, `jpeg`, `png`;
- `DocumentEditorScreen` для просмотра, переименования, удаления и шаринга файлов;
- базовое редактирование изображений: crop и rotate;
- OCR, перевод, QR-сканирование, подпись;
- сервисы для интеграции с backend.

## Требования

- Flutter `3.41.9+`
- Dart `3.9+`
- Android SDK
- JDK 17
- Android-устройство или эмулятор

## Запуск

```bash
flutter pub get
flutter run
```

## Анализ кода

В текущем окружении `dart analyze` может падать из-за запрета записи в системные папки `AppData`. Для стабильного анализа добавлен вспомогательный скрипт:

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\flutter_analyze.ps1
```

## Сборка Android

```bash
flutter build apk --release
```

## Важные ограничения

- package name пока шаблонный: `com.example.scanner_ap`
- release-подпись Android не настроена под production
- web-режим требует установленный Google Chrome
- Windows desktop требует `Visual Studio` с `Desktop development with C++`

## Связка с backend

Flutter-клиент использует API вида:

```text
http://<host>:3000/api
```

Адрес backend можно менять из интерфейса экрана облачных документов.
