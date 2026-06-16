# Aura Signature

Небольшое Flutter-приложение для рисования, предпросмотра и локального сохранения подписи.

## Что уже есть

- один нормальный `MaterialApp` без demo-обвязки
- сохранение подписи между перезапусками через `flutter_secure_storage`
- обновление и удаление подписи с главного экрана
- единый Android/Linux/macOS bundle id: `com.aurascanner.signature`

## Структура

```text
lib/
|- main.dart
|- home_screen.dart
`- signature_pad.dart
```

## Запуск

```bash
cd signature
flutter pub get
flutter run
```

## Ограничения

- release Android по-прежнему подписывается debug-ключом, пока не добавлен production keystore
- iOS test bundle id в `project.pbxproj` ещё шаблонный; если проект пойдёт в публикацию, его стоит подчистить тоже
