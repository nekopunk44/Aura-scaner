import dotenv from 'dotenv';

dotenv.config();

export const env = {
  port: parseInt(process.env.PORT || '3000', 10),
  mongoUri: process.env.MONGODB_URI || 'mongodb://localhost:27017/aura_scanner',
  jwtSecret: process.env.JWT_SECRET || 'changeme',
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
};

function validateEnv(): void {
  console.log('ENV CHECK:', Object.keys(process.env).filter(k => k.startsWith('MONGO') || k.startsWith('JWT')));
  const required = ['MONGODB_URI', 'JWT_SECRET'];
  const missing = required.filter(k => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(`Missing required env vars: ${missing.join(', ')}`);
  }
  if (env.jwtSecret === 'changeme' && env.nodeEnv === 'production') {
    throw new Error('JWT_SECRET must be changed in production');
  }
}
validateEnv();
