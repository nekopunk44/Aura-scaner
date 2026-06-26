import fs from 'fs';
import path from 'path';

import { Response } from 'express';
import multer from 'multer';

import { AuthRequest } from '../middleware/auth.middleware';
import { RefreshToken } from '../models/RefreshToken';
import { User } from '../models/User';
import { logger } from '../utils/logger';
import { isPremiumActive } from '../utils/premium';
import { blacklistToken } from '../utils/tokenBlacklist';

const avatarStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    const dir = path.join(__dirname, '../../uploads/avatars');
    fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, _file, cb) => {
    cb(null, `${(req as AuthRequest).userId}_${Date.now()}.jpg`);
  },
});

export const avatarUpload = multer({
  storage: avatarStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Только изображения'));
    }
  },
});

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function providerForUser(user: {
  authProvider?: string | null;
  googleSub?: string | null;
  appleSub?: string | null;
  vkUserId?: string | null;
  telegramId?: string | null;
  instagramUserId?: string | null;
}): string | null {
  if (user.authProvider) return user.authProvider;
  if (user.telegramId) return 'telegram';
  if (user.googleSub) return 'google';
  if (user.appleSub) return 'apple';
  if (user.vkUserId) return 'vk';
  if (user.instagramUserId) return 'instagram';
  return null;
}

function normalizeSessionId(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}

function fallbackSessionDate(session: { _id?: { getTimestamp?: () => Date } }) {
  try {
    return session._id?.getTimestamp?.() ?? new Date();
  } catch {
    return new Date();
  }
}

function serializeSession(
  session: {
    _id?: { getTimestamp?: () => Date };
    sessionId?: string | null;
    startedAt?: Date | string | null;
    lastUsedAt?: Date | string | null;
    userAgent?: string | null;
    ipAddress?: string | null;
  },
  currentSessionId?: string,
) {
  const fallbackDate = fallbackSessionDate(session);
  const normalizedSessionId =
    normalizeSessionId(session.sessionId ?? undefined) ??
    String(session._id ?? fallbackDate.getTime());
  const startedAt = session.startedAt ? new Date(session.startedAt) : fallbackDate;
  const lastUsedAt = session.lastUsedAt ? new Date(session.lastUsedAt) : startedAt;

  return {
    id: normalizedSessionId,
    startedAt,
    lastUsedAt,
    userAgent: session.userAgent ?? null,
    ipAddress: session.ipAddress ?? null,
    isCurrent: normalizedSessionId === currentSessionId,
  };
}

export async function getProfile(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  try {
    const user = await User.findById(req.userId).select(
      '_id email name createdAt isPremium premiumActivatedAt premiumExpiresAt authProvider avatarUrl googleSub appleSub vkUserId telegramId instagramUserId',
    );
    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }

    res.json({
      id: user._id,
      email: user.email,
      name: user.name,
      provider: providerForUser(user),
      avatarUrl: user.avatarUrl ?? null,
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

export async function updateProfile(
  req: AuthRequest,
  res: Response,
): Promise<void> {
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
      const existing = await User.findOne({
        email: updates.email,
        _id: { $ne: req.userId },
      });
      if (existing) {
        res.status(409).json({ message: 'Этот email уже используется' });
        return;
      }
    }

    const user = await User.findByIdAndUpdate(req.userId, updates, {
      new: true,
    }).select(
      '_id email name createdAt isPremium premiumActivatedAt premiumExpiresAt authProvider avatarUrl googleSub appleSub vkUserId telegramId instagramUserId',
    );

    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }

    res.json({
      id: user._id,
      email: user.email,
      name: user.name,
      provider: providerForUser(user),
      avatarUrl: user.avatarUrl ?? null,
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

export async function listSessions(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  try {
    const sessions = await RefreshToken.find({ userId: req.userId })
      .sort({ lastUsedAt: -1 })
      .select('sessionId startedAt lastUsedAt userAgent ipAddress')
      .lean();

    res.json({
      sessions: sessions.map((session) =>
        serializeSession(session, normalizeSessionId(req.sessionId)),
      ),
    });
  } catch (err) {
    logger.error('[listSessions]', { err });
    res.status(500).json({ message: 'Ошибка при получении списка сессий' });
  }
}

export async function revokeSession(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  const sessionId = normalizeSessionId(req.params.sessionId);
  if (!sessionId) {
    res.status(400).json({ message: 'Session id обязателен' });
    return;
  }

  try {
    const deleted = await RefreshToken.findOneAndDelete({
      userId: req.userId,
      sessionId,
    });

    if (!deleted) {
      res.status(404).json({ message: 'Сессия не найдена' });
      return;
    }

    if (req.accessToken && sessionId === req.sessionId) {
      await blacklistToken(req.accessToken);
    }

    res.json({ message: 'Сессия завершена' });
  } catch (err) {
    logger.error('[revokeSession]', { err });
    res.status(500).json({ message: 'Ошибка при завершении сессии' });
  }
}

export async function logoutOtherSessions(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  const currentSessionId = normalizeSessionId(req.sessionId);
  if (!currentSessionId) {
    res.status(400).json({ message: 'Текущая session id не передана' });
    return;
  }

  try {
    const result = await RefreshToken.deleteMany({
      userId: req.userId,
      sessionId: { $ne: currentSessionId },
    });
    res.json({ message: 'Остальные сессии завершены', count: result.deletedCount ?? 0 });
  } catch (err) {
    logger.error('[logoutOtherSessions]', { err });
    res.status(500).json({ message: 'Ошибка при завершении остальных сессий' });
  }
}

export async function updateAvatar(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  try {
    if (!req.file) {
      res.status(400).json({ message: 'Файл не передан' });
      return;
    }
    const avatarUrl = `/uploads/avatars/${req.file.filename}`;
    const user = await User.findByIdAndUpdate(
      req.userId,
      { avatarUrl },
      { new: true },
    ).select(
      '_id email name createdAt isPremium premiumActivatedAt premiumExpiresAt authProvider avatarUrl googleSub appleSub vkUserId telegramId instagramUserId',
    );
    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }
    res.json({
      id: user._id,
      email: user.email,
      name: user.name,
      provider: providerForUser(user),
      avatarUrl: user.avatarUrl ?? null,
      createdAt: user.createdAt,
      isPremium: isPremiumActive(user),
      premiumActivatedAt: user.premiumActivatedAt ?? null,
      premiumExpiresAt: user.premiumExpiresAt ?? null,
    });
  } catch (err) {
    logger.error('[updateAvatar]', { err });
    res.status(500).json({ message: 'Ошибка при обновлении аватара' });
  }
}

export async function logout(req: AuthRequest, res: Response): Promise<void> {
  if (req.accessToken) {
    await blacklistToken(req.accessToken);
  }

  try {
    if (req.sessionId) {
      await RefreshToken.deleteMany({
        userId: req.userId,
        sessionId: req.sessionId,
      });
    } else {
      await RefreshToken.deleteMany({ userId: req.userId });
    }

    res.json({ message: 'Выход выполнен' });
  } catch (err) {
    logger.error('[logout]', { err });
    res.status(500).json({ message: 'Ошибка при выходе из аккаунта' });
  }
}
