import * as Sentry from '@sentry/node';
import { logger } from './logger';

const dsn = process.env.SENTRY_DSN ?? '';

export const isSentryEnabled = dsn.length > 0;

/// Должна быть вызвана *самой первой* в app.ts — до import-ов контроллеров
/// и middleware, иначе Sentry не успеет инструментировать модули.
export function initSentry(): void {
  if (!isSentryEnabled) {
    logger.info('[sentry] DSN не задан, инициализация пропущена');
    return;
  }
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    // 10% перформанс-сэмплов — баланс между видимостью и квотой проекта.
    tracesSampleRate: 0.1,
  });
  logger.info('[sentry] инициализирован, environment=%s', process.env.NODE_ENV ?? 'development');
}
