import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { User } from '../models/User';
import { blacklistToken } from '../utils/tokenBlacklist';
import { RefreshToken } from '../models/RefreshToken';
import { logger } from '../utils/logger';
import { isPremiumActive } from '../utils/premium';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// GET /api/auth/profile
export async function getProfile(req: AuthRequest, res: Response): Promise<void> {
  try {
    const user = await User.findById(req.userId).select(
      '_id email name createdAt isPremium premiumActivatedAt premiumExpiresAt',
    );
    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }
    res.json({
      id: user._id,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
      isPremium: isPremiumActive(user),
      premiumActivatedAt: user.premiumActivatedAt ?? null,
      premiumExpiresAt: user.premiumExpiresAt ?? null,
    });
  } catch (err) {
    logger.error('[getProfile]', { err });
    res.status(500).json({ message: 'Ошибка при получении профиля' });
  }
}

// PATCH /api/auth/profile
export async function updateProfile(req: AuthRequest, res: Response): Promise<void> {
  const { name, email } = req.body as { name?: string; email?: string };

  if (!name && !email) {
    res.status(400).json({ message: 'Укажите name или email для обновления' });
    return;
  }

  const updates: Record<string, string> = {};

  if (name !== undefined) {
    const trimmed = name.trim();
    if (!trimmed) {
      res.status(400).json({ message: 'Имя не может быть пустым' });
      return;
    }
    updates.name = trimmed;
  }

  if (email !== undefined) {
    const trimmed = email.trim().toLowerCase();
    if (!EMAIL_REGEX.test(trimmed)) {
      res.status(400).json({ message: 'Некорректный формат email' });
      return;
    }
    updates.email = trimmed;
  }

  try {
    if (updates.email) {
      const existing = await User.findOne({ email: updates.email, _id: { $ne: req.userId } });
      if (existing) {
        res.status(409).json({ message: 'Этот email уже используется' });
        return;
      }
    }

    const user = await User.findByIdAndUpdate(req.userId, updates, { new: true }).select(
      '_id email name createdAt isPremium premiumActivatedAt premiumExpiresAt'
    );

    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }

    res.json({
      id: user._id,
      email: user.email,
      name: user.name,
      createdAt: user.createdAt,
      isPremium: isPremiumActive(user),
      premiumActivatedAt: user.premiumActivatedAt ?? null,
      premiumExpiresAt: user.premiumExpiresAt ?? null,
    });
  } catch (err) {
    logger.error('[updateProfile]', { err });
    res.status(500).json({ message: 'Ошибка при обновлении профиля' });
  }
}

// POST /api/auth/logout
export async function logout(req: AuthRequest, res: Response): Promise<void> {
  const header = req.headers.authorization;
  if (header?.startsWith('Bearer ')) {
    await blacklistToken(header.slice(7));
  }
  // Удаляем все refresh tokens пользователя
  await RefreshToken.deleteMany({ userId: req.userId });
  res.json({ message: 'Выход выполнен' });
}
