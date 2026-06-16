# Aura Scanner

Aura Scanner is a multi-part repository for document capture, OCR, cloud sync, and signature workflows.

## Repository Layout

```text
backend/      Express + TypeScript API
scanner_ap/   Main Flutter client
signature/    Signature-focused Flutter mini app
scripts/      Local utility scripts
branding/     Brand assets
```

## Current Status

- Backend auth, token rotation, and social login flows are implemented
- OAuth redirect handling uses the production app id `com.aurascanner.app`
- `scanner_ap` is analyzable and its core auth config tests pass
- `signature` now persists a saved signature locally and passes analysis and tests
- Project documentation has been refreshed to match the current codebase

## Quick Start

### Backend

```bash
cd backend
npm install
cp .env.example .env
npm run dev
```

### Main Flutter App

```bash
cd scanner_ap
flutter pub get
flutter run
```

### Signature App

```bash
cd signature
flutter pub get
flutter run
```

## Verification

Validated locally on June 16, 2026:

```bash
cd backend && npm test
cd backend && npm run build
cd scanner_ap && flutter analyze
cd scanner_ap && flutter test test/services/social_auth_service_test.dart test/services/server_config_test.dart
cd signature && flutter analyze
cd signature && flutter test
```

## Known Gaps

- `scanner_ap` still uses the internal Dart package name `scanner_ap`
- Full end-to-end device testing is still needed for production confidence
- Real production OAuth credentials and mobile store signing assets are still required

## License

MIT
