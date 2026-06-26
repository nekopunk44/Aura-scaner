// Sentry должен инициализироваться до импорта express и контроллеров,
// чтобы автоинструментация подтянулась корректно.
import { initSentry } from './utils/sentry';
initSentry();

import path from 'path';
import express from 'express';
import * as Sentry from '@sentry/node';
import cors from 'cors';
import helmet from 'helmet';
import mongoose from 'mongoose';
import morgan from 'morgan';
import { rateLimit } from 'express-rate-limit';
import { env } from './config/env';
import { connectDatabase, setupGracefulShutdown } from './config/database';
import { logger } from './utils/logger';
import authRoutes from './routes/auth.routes';
import documentsRoutes from './routes/documents.routes';
import aiRoutes from './routes/ai.routes';
import premiumRoutes from './routes/premium.routes';
import { vkCallback } from './controllers/vk.controller';
import { startPremiumSweeper } from './utils/premium';

const app = express();

// Trust Railway / reverse-proxy forwarded headers so req.protocol = 'https'
app.set('trust proxy', 1);

// Security headers — разрешаем скрипт Telegram Login Widget
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", 'https://telegram.org'],
      frameSrc: ["'self'", 'https://telegram.org', 'https://oauth.telegram.org'],
      imgSrc: ["'self'", 'https://telegram.org', 'https://*.telegram.org', 'data:'],
      objectSrc: ["'none'"],
    },
  },
}));

// CORS: мобильный клиент (Flutter) запросы делает без Origin —
// разрешаем их. Браузеры посылают Origin — для них работает whitelist.
// Список задаётся через CORS_ALLOWED_ORIGINS (CSV). В dev по умолчанию
// разрешаем localhost. В production без явно заданного списка — отказ
// (мобильный клиент работать продолжит, т.к. у него нет Origin).
const corsAllowed = (process.env.CORS_ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const corsDevDefaults =
  env.nodeEnv === 'production'
    ? []
    : ['http://localhost:3000', 'http://localhost:5173', 'http://127.0.0.1:3000'];
const allowedOrigins = new Set<string>([...corsAllowed, ...corsDevDefaults]);

// Delegate-форма (с доступом к req): разрешаем same-origin запросы.
// Страницы Telegram/VK-логина отдаёт сам бэкенд, и они POST'ят обратно
// на свой же хост (/auth/telegram/exchange и т.п.) — браузер при этом
// шлёт Origin, и без этой проверки CORS их резал.
const corsDelegate: cors.CorsOptionsDelegate<express.Request> = (req, cb) => {
  const base: cors.CorsOptions = {
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  };
  const origin = req.headers.origin;

  // Нет Origin — нативный клиент или server-to-server, пропускаем.
  if (!origin) return cb(null, { ...base, origin: true });
  // Явный whitelist из CORS_ALLOWED_ORIGINS.
  if (allowedOrigins.has(origin)) return cb(null, { ...base, origin: true });
  // Same-origin: за прокси (Railway) внутренний протокол http, а внешний
  // https — поэтому сравниваем только host, без схемы.
  try {
    if (new URL(origin).host === req.headers.host) {
      return cb(null, { ...base, origin: true });
    }
  } catch {
    // битый Origin — провалится в отказ ниже
  }
  logger.warn('[cors] Blocked origin: %s', origin);
  cb(new Error(`CORS: origin ${origin} не разрешён`));
};

app.use(cors(corsDelegate));

// HTTP request logging через Morgan → Winston
app.use(morgan('combined', { stream: { write: (msg) => logger.http(msg.trim()) } }));

// JSON body с лимитом 10 MB чтобы нельзя было положить сервер гигантским payload
app.use(express.json({ limit: '10mb' }));

// Аватары и другие загруженные файлы
app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

// Rate limiting для auth-эндпоинтов (защита от брутфорса)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много запросов. Попробуйте через 15 минут.' },
});

// Строгий лимит для входа (login/register/social/oauth-exchange).
// Атаки типа credential stuffing и brute force бьют именно сюда,
// поэтому окно меньше, а порог жёстче.
const strictAuthLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 минут
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много попыток входа. Попробуйте через 5 минут.' },
});

// Общий лимит для остальных API
const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 минута
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много запросов. Попробуйте позже.' },
});

app.get('/health', (_req, res) => {
  const dbStatus = mongoose.connection.readyState === 1 ? 'ok' : 'error';
  const status = dbStatus === 'ok' ? 200 : 503;
  res.status(status).json({ status: dbStatus === 'ok' ? 'ok' : 'degraded', db: dbStatus });
});

// Чувствительные эндпоинты (login/register/social/oauth-exchange) получают
// строгий лимит сверху общего authLimiter.
app.use('/api/auth/login', strictAuthLimiter);
app.use('/api/auth/register', strictAuthLimiter);
app.use('/api/auth/social', strictAuthLimiter);
app.use('/api/auth/oauth/exchange', strictAuthLimiter);
app.use('/api/auth/telegram/exchange', strictAuthLimiter);

app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/documents', apiLimiter, documentsRoutes);
app.use('/api/ai', apiLimiter, aiRoutes);
app.use('/api/premium', apiLimiter, premiumRoutes);

// VK ID callback на корне (требование VK + соответствие Universal Link /
// associated domain для возврата в приложение)
app.get('/vk_id_redirect', authLimiter, vkCallback);

// Sentry перехватывает ошибки контроллеров до нашего хендлера. setupExpressErrorHandler
// внутри проверяет init() и тихо ноупит, если DSN не задан.
Sentry.setupExpressErrorHandler(app);

// Глобальный error handler — перехватывает всё что вылетело из контроллеров
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('[error]', { message: err.message });
  const status = (err as { status?: number }).status ?? 500;
  res.status(status).json({ message: err.message || 'Внутренняя ошибка сервера' });
});

connectDatabase()
  .then(() => {
    app.listen(env.port, () => {
      logger.info(`Server running on port ${env.port}`);
    });
    // Чистка истёкших Premium-подписок (раз в час + сразу при старте)
    startPremiumSweeper();
  })
  .catch((err) => {
    logger.error('Failed to connect to MongoDB:', { err });
    process.exit(1);
  });

setupGracefulShutdown();

export default app;
