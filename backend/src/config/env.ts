import dotenv from 'dotenv';

dotenv.config();

// JWT_SECRET валидируется через validateEnv() — если пусто, процесс упадёт при старте.
// Никаких дефолтов в исходниках: иначе разработчик может случайно задеплоить
// продакшен с предсказуемым секретом и подделывать чужие токены.
const _jwtSecret = process.env.JWT_SECRET ?? '';

// CodeFormer fidelity (2-я стадия восстановления): ближе к 1 = вернее лицам
// (меньше «кукольности»/пластика), ближе к 0 = резче, но рискует «приукрасить».
const _codeformerFidelity = (() => {
  const v = parseFloat(process.env.REPLICATE_CODEFORMER_FIDELITY ?? '');
  return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.85;
})();

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
  // Список моделей OpenRouter через запятую — контроллер пробует их по
  // очереди и берёт первую, что ответит (фолбэк-цепочка). ВСЕ должны
  // поддерживать vision (запросы содержат картинки). Набор free-моделей у
  // OpenRouter волатилен и часть залочена на уровне аккаунта — цепочка даёт
  // максимальный шанс, что хоть одна доступна. Переопределяется через env
  // OPENROUTER_MODEL (один слаг или список через запятую).
  // Проверено openrouter.ai/api/v1/models (15.06.2026).
  openRouterModel:
    process.env.OPENROUTER_MODEL ||
    'google/gemma-4-31b-it:free,google/gemma-4-26b-a4b-it:free,nvidia/nemotron-nano-12b-v2-vl:free',
  openRouterOcrModel: process.env.OPENROUTER_OCR_MODEL || 'openrouter/free',
  // Replicate — восстановление старых фото. По умолчанию Microsoft
  // «Bringing Old Photos Back to Life»: убирает царапины/трещины и бережно
  // реставрирует, не перерисовывая лица заново (в отличие от GFPGAN, который
  // меняет идентичность). Альтернативы (через REPLICATE_RESTORE_MODEL):
  //   sczhou/codeformer  — вернее к лицам, но НЕ убирает царапины фона;
  //   tencentarc/gfpgan  — только лица, агрессивно «придумывает» их заново.
  // Вход подбирается под модель в buildRestoreInput(). Без токена → 503.
  replicateApiToken: process.env.REPLICATE_API_TOKEN || '',
  replicateRestoreModel:
    process.env.REPLICATE_RESTORE_MODEL ||
    'microsoft/bringing-old-photos-back-to-life',
  // 2-я стадия (уточнение): CodeFormer — чёткость лиц + апскейл/детали поверх
  // результата 1-й стадии. Пусто = выключить вторую стадию.
  replicateRefineModel:
    process.env.REPLICATE_RESTORE_REFINE ?? 'sczhou/codeformer',
  replicateCodeformerFidelity: _codeformerFidelity,
  // FLUX Fill reconstructs only white areas of the supplied mask. Keeping this
  // model configurable lets deployments switch providers without an app update.
  replicateInpaintModel:
    process.env.REPLICATE_INPAINT_MODEL ||
    'black-forest-labs/flux-fill-pro',
  // Speech-to-text for voice notes. This remains configurable so a deployment
  // can switch Whisper-compatible models without requiring an app update.
  replicateTranscribeModel:
    process.env.REPLICATE_TRANSCRIBE_MODEL || 'openai/whisper',
  // Удаление водяного знака со ВСЕГО кадра без маски: инструкционный редактор
  // (FLUX Kontext) убирает сплошные/тайловые знаки и достраивает сцену.
  replicateDewatermarkModel:
    process.env.REPLICATE_DEWATERMARK_MODEL ||
    'black-forest-labs/flux-kontext-pro',
  // Apple Sign In
  appleBundleId: process.env.APPLE_BUNDLE_ID || 'com.aurascanner.app',
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
