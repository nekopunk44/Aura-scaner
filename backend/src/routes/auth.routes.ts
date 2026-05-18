import { Router } from 'express';
import { register, login, changePassword, refreshAccessToken } from '../controllers/auth.controller';
import { socialLogin, googleCallback } from '../controllers/social.auth.controller';
import { getProfile, updateProfile, logout } from '../controllers/profile.controller';
import { telegramLoginPage, telegramCallback } from '../controllers/telegram.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/social', socialLogin);
router.post('/refresh', refreshAccessToken);

// Telegram Login Widget flow (public endpoints)
router.get('/telegram/login', telegramLoginPage);
router.get('/telegram/callback', telegramCallback);

// Google server-side OAuth callback
router.get('/google/callback', googleCallback);

// Профиль и logout — требуют авторизации
router.get('/profile', authMiddleware, getProfile);
router.patch('/profile', authMiddleware, updateProfile);
router.post('/logout', authMiddleware, logout);
router.post('/change-password', authMiddleware, changePassword);

export default router;
