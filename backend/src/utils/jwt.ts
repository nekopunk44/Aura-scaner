import jwt from 'jsonwebtoken';
import { env } from '../config/env';

export function signToken(userId: string): string {
  return jwt.sign({ id: userId }, env.jwtSecret, { expiresIn: env.jwtExpiresIn } as jwt.SignOptions);
}

export function verifyToken(token: string): { id: string } {
  return jwt.verify(token, env.jwtSecret) as { id: string };
}

export function signRefreshToken(userId: string): string {
  const secret = env.jwtRefreshSecret || env.jwtSecret + '_refresh';
  return jwt.sign({ id: userId }, secret, { expiresIn: env.jwtRefreshExpiresIn } as jwt.SignOptions);
}

export function verifyRefreshToken(token: string): { id: string } {
  const secret = env.jwtRefreshSecret || env.jwtSecret + '_refresh';
  return jwt.verify(token, secret) as { id: string };
}
