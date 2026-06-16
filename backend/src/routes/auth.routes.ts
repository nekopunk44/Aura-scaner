import { Router } from 'express';
import { register, login, changePassword, refreshAccessToken } from '../controllers/auth.controller';
import { socialLogin, googleCallback, exchangeOAuthCode } from '../controllers/social.auth.controller';
import {
  getProfile,
  listSessions,
  logout,
  logoutOtherSessions,
  revokeSession,
  updateProfile,
} from '../controllers/profile.controller';
import { telegramLoginPage, telegramCallback, telegramExchange } from '../controllers/telegram.controller';
import { vkLoginPage } from '../controllers/vk.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/social', socialLogin);
router.post('/refresh', refreshAccessToken);

// Обмен одноразового OAuth-кода на JWT (deep link не несёт сами токены)
router.post('/oauth/exchange', exchangeOAuthCode);

// Telegram Login Widget flow (public endpoints)
router.get('/telegram/login', telegramLoginPage);
router.get('/telegram/callback', telegramCallback);
router.post('/telegram/exchange', telegramExchange);

// Google server-side OAuth callback
router.get('/google/callback', googleCallback);

// VK ID OAuth — login entrypoint (callback регистрируется на /vk_id_redirect в app.ts,
// потому что должен совпадать с Android Universal Link и iOS associated domain)
router.get('/vk/login', vkLoginPage);

// Профиль и logout — требуют авторизации
router.get('/profile', authMiddleware, getProfile);
router.patch('/profile', authMiddleware, updateProfile);
router.get('/sessions', authMiddleware, listSessions);
router.delete('/sessions/:sessionId', authMiddleware, revokeSession);
router.post('/logout-others', authMiddleware, logoutOtherSessions);
router.post('/logout', authMiddleware, logout);
router.post('/change-password', authMiddleware, changePassword);

export default router;
