import { Request, Response } from 'express';
import { User } from '../models/User';
import { signToken, signRefreshToken, verifyRefreshToken } from '../utils/jwt';
import { AuthRequest } from '../middleware/auth.middleware';
import { RefreshToken } from '../models/RefreshToken';
import { logger } from '../utils/logger';

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

    const user = await User.create({ email: trimmedEmail, password, name: trimmedName });
    const token = signToken(String(user._id));
    const refreshToken = signRefreshToken(String(user._id));
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await RefreshToken.create({ userId: user._id, token: refreshToken, expiresAt });

    res.status(201).json({
      token,
      refreshToken,
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

    const token = signToken(String(user._id));
    const refreshToken = signRefreshToken(String(user._id));
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await RefreshToken.create({ userId: user._id, token: refreshToken, expiresAt });

    res.json({
      token,
      refreshToken,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[login]', { err });
    res.status(500).json({ message: 'Ошибка при входе' });
  }
}

// POST /api/auth/change-password
export async function changePassword(req: AuthRequest, res: Response): Promise<void> {
  const { currentPassword, newPassword } = req.body;
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
    res.json({ message: 'Пароль изменён' });
  } catch (err) {
    logger.error('[changePassword]', { err });
    res.status(500).json({ message: 'Ошибка при смене пароля' });
  }
}

// POST /api/auth/refresh
export async function refreshAccessToken(req: Request, res: Response): Promise<void> {
  const { refreshToken } = req.body;
  if (!refreshToken) {
    res.status(400).json({ message: 'Refresh token обязателен' });
    return;
  }
  try {
    const payload = verifyRefreshToken(refreshToken);
    const stored = await RefreshToken.findOne({ token: refreshToken, userId: payload.id });
    if (!stored) {
      res.status(401).json({ message: 'Refresh token не найден или истёк' });
      return;
    }
    const user = await User.findById(payload.id).select('_id email name');
    if (!user) {
      res.status(401).json({ message: 'Пользователь не найден' });
      return;
    }
    // Ротация: удаляем старый, выдаём новый
    await stored.deleteOne();
    const newRefreshToken = signRefreshToken(String(user._id));
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await RefreshToken.create({ userId: user._id, token: newRefreshToken, expiresAt });
    const accessToken = signToken(String(user._id));
    res.json({
      token: accessToken,
      refreshToken: newRefreshToken,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[refreshAccessToken]', { err });
    res.status(401).json({ message: 'Недействительный refresh token' });
  }
}
