# Aura Scanner

Main Flutter client for the `Aura Scanner` project.

## What it does

- Scans documents, passports, and ID cards
- Imports local files
- Lets users review and manage saved documents
- Runs OCR and translation flows
- Supports PDF-related operations
- Syncs with the backend API

## Requirements

- Flutter `3.41.9+`
- Dart `3.9+`
- Android SDK
- JDK 17
- Android device or emulator

## Run

```bash
flutter pub get
flutter run
```

## Analysis

If `dart analyze` is blocked by local environment restrictions on Windows, use:

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\flutter_analyze.ps1
```

## Android release build

```bash
flutter build apk --release
```

## Backend connection

The Flutter client uses an API endpoint in this format:

```text
http://<host>:3000/api
```

The backend address can be changed from the app settings flow for cloud features.
