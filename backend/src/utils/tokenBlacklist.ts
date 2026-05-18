import jwt from 'jsonwebtoken';
import { RevokedToken } from '../models/RevokedToken';

export async function blacklistToken(token: string): Promise<void> {
  try {
    const decoded = jwt.decode(token) as { exp?: number } | null;
    const expiresAt = decoded?.exp
      ? new Date(decoded.exp * 1000)
      : new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    await RevokedToken.create({ token, expiresAt });
  } catch {
    // ignore duplicate key errors (double logout)
  }
}

export async function isTokenBlacklisted(token: string): Promise<boolean> {
  const found = await RevokedToken.findOne({ token }).lean();
  return found !== null;
}
