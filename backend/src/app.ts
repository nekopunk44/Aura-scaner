import express from 'express';
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

const app = express();

// Security headers
app.use(helmet());

// CORS — мобильный клиент не отправляет Origin, поэтому разрешаем всё,
// но явно ограничиваем методы и заголовки
app.use(cors({
  methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// HTTP request logging через Morgan → Winston
app.use(morgan('combined', { stream: { write: (msg) => logger.http(msg.trim()) } }));

// JSON body с лимитом 10 MB чтобы нельзя было положить сервер гигантским payload
app.use(express.json({ limit: '10mb' }));

// Rate limiting для auth-эндпоинтов (защита от брутфорса)
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 минут
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Слишком много запросов. Попробуйте через 15 минут.' },
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

app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/documents', apiLimiter, documentsRoutes);

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
  })
  .catch((err) => {
    logger.error('Failed to connect to MongoDB:', { err });
    process.exit(1);
  });

setupGracefulShutdown();

export default app;
