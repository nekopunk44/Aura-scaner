import dotenv from 'dotenv';

dotenv.config();

// JWT_SECRET валидируется через validateEnv() — если пусто, процесс упадёт при старте.
// Никаких дефолтов в исходниках: иначе разработчик может случайно задеплоить
// продакшен с предсказуемым секретом и подделывать чужие токены.
const _jwtSecret = process.env.JWT_SECRET ?? '';

export const env = {
  port: parseInt(process.env.PORT || '3000', 10),
  mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/aura_scanner',
  jwtSecret: _jwtSecret,
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  uploadDir: process.env.UPLOAD_DIR || 'uploads',
  maxFileSizeMb: parseInt(process.env.MAX_FILE_SIZE_MB || '50', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  logLevel: process.env.LOG_LEVEL || 'info',
  jwtRefreshSecret: process.env.JWT_REFRESH_SECRET || '',
  jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
  telegramBotToken: process.env.TELEGRAM_BOT_TOKEN || '',
  telegramBotUsername: process.env.TELEGRAM_BOT_USERNAME || '',
  vkAppId: process.env.VK_APP_ID || '',
  instagramAppId: process.env.INSTAGRAM_APP_ID || '',
  instagramAppSecret: process.env.INSTAGRAM_APP_SECRET || '',
  googleClientId: process.env.GOOGLE_CLIENT_ID || '',
  googleClientSecret: process.env.GOOGLE_CLIENT_SECRET || '',
  openRouterApiKey: process.env.OPENROUTER_API_KEY || '',
  // Модель OpenRouter. ДОЛЖНА поддерживать vision (запросы содержат картинки).
  // gemma-3 мультимодальна; прежняя 'gemma-4-31b' не существовала → OpenRouter
  // отвечал ошибкой, а контроллер отдавал 502.
  openRouterModel: process.env.OPENROUTER_MODEL || 'google/gemma-3-27b-it:free',
  // Apple Sign In
  appleBundleId: process.env.APPLE_BUNDLE_ID || 'com.example.scannerAp',
  // Apple App Store Server API (для проверки receipt)
  appleSharedSecret: process.env.APPLE_SHARED_SECRET || '',
  appleUseSandbox: process.env.APPLE_USE_SANDBOX === 'true',
  // Google Play Developer API (для проверки receipt)
  googlePlayPackageName: process.env.GOOGLE_PLAY_PACKAGE_NAME || '',
  googlePlayServiceAccountJson: process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || '',
  // Sentry — мониторинг ошибок (опционально)
  sentryDsn: process.env.SENTRY_DSN || '',
};

function validateEnv(): void {
  const required = ['MONGODB_URI', 'JWT_SECRET'];
  const missing = required.filter(k => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(`Missing required env vars: ${missing.join(', ')}`);
  }
  // JWT_SECRET минимум 32 символа: короткий секрет = слабая HMAC-устойчивость
  if (env.jwtSecret.length < 32) {
    throw new Error('JWT_SECRET слишком короткий: задайте минимум 32 символа');
  }
  // Известные дефолты из старых конфигов / документации
  const knownWeak = ['changeme', 'secret', 'jwt_secret', 'your-secret-key'];
  if (knownWeak.includes(env.jwtSecret.toLowerCase())) {
    throw new Error(`JWT_SECRET установлен в небезопасное значение по умолчанию (${env.jwtSecret})`);
  }
}
validateEnv();
