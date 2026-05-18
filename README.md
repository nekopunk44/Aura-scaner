# Aura Scanner

A Flutter application for scanning, importing, viewing, and storing documents with cloud synchronization.

## Structure

```
├── scanner_ap/   # Flutter mobile app (Android / iOS)
├── backend/      # Node.js / TypeScript REST API
├── signature/    # Signature mini-project
└── scripts/      # Utility scripts
```

## Features

- Document scanning (standard, passport, ID card)
- OCR with Russian language support (Tesseract + ML Kit)
- PDF tools: compress, merge, reorder, extract pages
- Image editing: brightness, contrast, saturation, hue
- QR code scanner
- Two-way cloud sync with offline support
- Auth: email/password + Google, VK, Telegram, Instagram OAuth
- JWT access + refresh token rotation

## Backend

Built with Express + TypeScript + MongoDB + JWT.

```bash
cd backend
cp .env.example .env   # fill in your values
npm install
npm run dev
```

See `backend/.env.example` for required environment variables.

## Flutter App

```bash
cd scanner_ap
flutter pub get
flutter run
```

Requires Flutter 3.x. Configure the server URL in app Settings after launch.

## License

MIT
