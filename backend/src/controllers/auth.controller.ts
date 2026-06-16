import { Request, Response } from 'express';

import { AuthRequest } from '../middleware/auth.middleware';
import { RefreshToken } from '../models/RefreshToken';
import { User } from '../models/User';
import { logger } from '../utils/logger';
import {
  getRequestSessionContext,
  issueSessionTokens,
  rotateSessionTokens,
} from '../utils/sessionTokens';
import { verifyRefreshToken } from '../utils/jwt';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function register(req: Request, res: Response): Promise<void> {
  const { email, password, name } = req.body as {
    email?: string;
    password?: string;
    name?: string;
  };

  if (!email || !password || !name) {
    res.status(400).json({ message: 'Email, пароль и имя обязательны' });
    return;
  }

  const trimmedEmail = email.trim().toLowerCase();
  if (!EMAIL_REGEX.test(trimmedEmail)) {
    res.status(400).json({ message: 'Некорректный формат email' });
    return;
  }

  if (password.length < 6) {
    res.status(400).json({ message: 'Пароль должен содержать минимум 6 символов' });
    return;
  }

  const trimmedName = name.trim();
  if (!trimmedName) {
    res.status(400).json({ message: 'Имя не может быть пустым' });
    return;
  }

  try {
    const existing = await User.findOne({ email: trimmedEmail });
    if (existing) {
      res.status(409).json({ message: 'Пользователь с таким email уже существует' });
      return;
    }

    const user = await User.create({
      email: trimmedEmail,
      password,
      name: trimmedName,
    });
    const { token, refreshToken, sessionId } = await issueSessionTokens(
      user._id,
      getRequestSessionContext(req),
    );

    res.status(201).json({
      token,
      refreshToken,
      sessionId,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[register]', { err });
    res.status(500).json({ message: 'Ошибка при регистрации' });
  }
}

export async function login(req: Request, res: Response): Promise<void> {
  const { email, password } = req.body as { email?: string; password?: string };

  if (!email || !password) {
    res.status(400).json({ message: 'Email и пароль обязательны' });
    return;
  }

  try {
    const user = await User.findOne({ email: email.trim().toLowerCase() });
    if (!user || !(await user.comparePassword(password))) {
      res.status(401).json({ message: 'Неверный email или пароль' });
      return;
    }

    const { token, refreshToken, sessionId } = await issueSessionTokens(
      user._id,
      getRequestSessionContext(req),
    );

    res.json({
      token,
      refreshToken,
      sessionId,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[login]', { err });
    res.status(500).json({ message: 'Ошибка при входе' });
  }
}

export async function changePassword(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  const { currentPassword, newPassword } = req.body as {
    currentPassword?: string;
    newPassword?: string;
  };

  if (!currentPassword || !newPassword) {
    res.status(400).json({ message: 'Текущий и новый пароль обязательны' });
    return;
  }

  if (newPassword.length < 6) {
    res.status(400).json({ message: 'Новый пароль должен содержать минимум 6 символов' });
    return;
  }

  try {
    const user = await User.findById(req.userId);
    if (!user || !(await user.comparePassword(currentPassword))) {
      res.status(401).json({ message: 'Неверный текущий пароль' });
      return;
    }

    user.password = newPassword;
    await user.save();

    if (req.sessionId) {
      await RefreshToken.deleteMany({
        userId: req.userId,
        sessionId: { $ne: req.sessionId },
      });
    } else {
      await RefreshToken.deleteMany({ userId: req.userId });
    }

    res.json({ message: 'Пароль изменён' });
  } catch (err) {
    logger.error('[changePassword]', { err });
    res.status(500).json({ message: 'Ошибка при смене пароля' });
  }
}

export async function refreshAccessToken(
  req: Request,
  res: Response,
): Promise<void> {
  const { refreshToken, sessionId } = req.body as {
    refreshToken?: string;
    sessionId?: string;
  };

  if (!refreshToken) {
    res.status(400).json({ message: 'Refresh token обязателен' });
    return;
  }

  try {
    const payload = verifyRefreshToken(refreshToken);
    const stored = await RefreshToken.findOne({
      token: refreshToken,
      userId: payload.id,
    });

    if (!stored) {
      res.status(401).json({ message: 'Refresh token не найден или истёк' });
      return;
    }

    const user = await User.findById(payload.id).select('_id email name');
    if (!user) {
      res.status(401).json({ message: 'Пользователь не найден' });
      return;
    }
    const rotated = await rotateSessionTokens(stored, {
      sessionId,
      ...getRequestSessionContext(req),
    });

    res.json({
      token: rotated.token,
      refreshToken: rotated.refreshToken,
      sessionId: rotated.sessionId,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[refreshAccessToken]', { err });
    res.status(401).json({ message: 'Недействительный refresh token' });
  }
}
