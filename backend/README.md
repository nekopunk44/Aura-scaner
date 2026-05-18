# Aura Scanner Backend

Backend для `Aura Scanner` на `Express + TypeScript + MongoDB`.

## Что умеет

- health-check через `GET /health`
- авторизация через `/api/auth`
- работа с документами через `/api/documents`
- загрузка файлов через `multer`

## Требования

- Node.js 20+
- MongoDB

## Быстрый старт

1. Установить зависимости:

```bash
npm install
```

2. Создать `.env` на основе `.env.example`.

3. Запустить backend в dev-режиме:

```bash
npm run dev
```

4. Или собрать production-версию:

```bash
npm run build
npm start
```

## Smoke-проверка

После сборки можно прогнать локальную smoke-проверку backend:

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\backend_smoke_test.ps1
```

Скрипт проверяет:

- `GET /health`
- регистрацию пользователя
- список документов
- upload
- rename
- download
- delete

## Переменные окружения

```env
PORT=3000
MONGODB_URI=mongodb://localhost:27017/aura_scanner
JWT_SECRET=change-me-in-production
JWT_EXPIRES_IN=7d
UPLOAD_DIR=uploads
MAX_FILE_SIZE_MB=50
```

## Примечания

- Без доступной MongoDB сервер не стартует.
- Flutter-клиент должен указывать на backend URL вида `http://<host>:3000/api`.
