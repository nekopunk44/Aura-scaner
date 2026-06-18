# Aura Scanner Backend

Express + TypeScript backend for Aura Scanner.

## Responsibilities

- Email/password auth
- Refresh token rotation
- Social login callbacks and OAuth code exchange
- User profile APIs
- Document upload, listing, rename, download, and delete
- Health checks and runtime validation

## Requirements

- Node.js 20+
- MongoDB

## Setup

```bash
npm install
cp .env.example .env
```

Fill in the required values in `.env` before running the server.

## Run

```bash
npm run dev
```

## Build And Test

```bash
npm run build
npm test
```

## Smoke Test

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\backend_smoke_test.ps1
```

## Important Environment Variables

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/aura_scanner
JWT_SECRET=
JWT_REFRESH_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
TELEGRAM_BOT_TOKEN=
VK_APP_ID=
INSTAGRAM_APP_ID=
INSTAGRAM_APP_SECRET=
OPENROUTER_API_KEY=
OPENROUTER_MODEL=
OPENROUTER_OCR_MODEL=openrouter/free
APPLE_BUNDLE_ID=com.aurascanner.app
GOOGLE_PLAY_PACKAGE_NAME=com.aurascanner.app
```

## Notes

- The server refuses to start if required auth secrets are missing
- Social login is linked by verified provider identity, not by client-supplied email
- Android deep link generation expects the production package id `com.aurascanner.app`
- OCR uses OpenRouter through the backend proxy; keep `OPENROUTER_API_KEY` only on the server/Railway
