import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../utils/jwt';
import { isTokenBlacklisted } from '../utils/tokenBlacklist';
import { User } from '../models/User';

export interface AuthRequest extends Request {
  userId?: string;
  sessionId?: string;
  accessToken?: string;
}

export async function authMiddleware(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    res.status(401).json({ message: 'Токен не предоставлен' });
    return;
  }

  const token = header.slice(7);
  if (await isTokenBlacklisted(token)) {
    res.status(401).json({ message: 'Токен отозван. Войдите снова.' });
    return;
  }
  try {
    const payload = verifyToken(token);
    const user = await User.findById(payload.id).select('_id');
    if (!user) {
      res.status(401).json({ message: 'Пользователь не найден' });
      return;
    }
    req.userId = payload.id;
    req.accessToken = token;
    const sessionIdHeader = req.headers['x-session-id'];
    if (typeof sessionIdHeader === 'string' && sessionIdHeader.trim().length > 0) {
      req.sessionId = sessionIdHeader.trim();
    }
    next();
  } catch {
    res.status(401).json({ message: 'Недействительный или истёкший токен' });
  }
}
