import crypto from 'crypto';
import { Request } from 'express';
import mongoose from 'mongoose';

import { IRefreshToken, RefreshToken } from '../models/RefreshToken';
import { signRefreshToken, signToken } from './jwt';

export interface SessionContext {
  sessionId?: string;
  startedAt?: Date;
  userAgent?: string;
  ipAddress?: string;
}

export interface IssuedSessionTokens {
  token: string;
  refreshToken: string;
  sessionId: string;
}

function trimTo(value: string | undefined, maxLength: number): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;
  return trimmed.slice(0, maxLength);
}

function createSessionId(): string {
  return typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : crypto.randomBytes(16).toString('hex');
}

export function getRequestSessionContext(req: Request): SessionContext {
  const forwarded = req.headers['x-forwarded-for'];
  const forwardedIp =
    typeof forwarded === 'string'
      ? forwarded.split(',')[0]
      : Array.isArray(forwarded)
        ? forwarded[0]
        : undefined;

  return {
    userAgent: trimTo(req.get('user-agent'), 500),
    ipAddress: trimTo(forwardedIp ?? req.socket.remoteAddress ?? undefined, 120),
  };
}

async function createRefreshTokenRecord(params: {
  userId: mongoose.Types.ObjectId | string;
  refreshToken: string;
  sessionId: string;
  startedAt: Date;
  lastUsedAt: Date;
  userAgent?: string;
  ipAddress?: string;
}): Promise<void> {
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await RefreshToken.create({
    userId: params.userId,
    sessionId: params.sessionId,
    token: params.refreshToken,
    startedAt: params.startedAt,
    lastUsedAt: params.lastUsedAt,
    userAgent: params.userAgent,
    ipAddress: params.ipAddress,
    expiresAt,
  });
}

export async function issueSessionTokens(
  userId: mongoose.Types.ObjectId | string,
  context: SessionContext = {},
): Promise<IssuedSessionTokens> {
  const token = signToken(String(userId));
  const refreshToken = signRefreshToken(String(userId));
  const now = new Date();
  const sessionId = trimTo(context.sessionId, 120) ?? createSessionId();
  const startedAt = context.startedAt ?? now;

  await createRefreshTokenRecord({
    userId,
    refreshToken,
    sessionId,
    startedAt,
    lastUsedAt: now,
    userAgent: context.userAgent,
    ipAddress: context.ipAddress,
  });

  return { token, refreshToken, sessionId };
}

export async function rotateSessionTokens(
  stored: IRefreshToken,
  context: SessionContext = {},
): Promise<IssuedSessionTokens> {
  const token = signToken(String(stored.userId));
  const refreshToken = signRefreshToken(String(stored.userId));
  const now = new Date();

  const sessionId = trimTo(context.sessionId, 120) ?? stored.sessionId;
  const startedAt = stored.startedAt ?? now;

  await stored.deleteOne();
  await createRefreshTokenRecord({
    userId: stored.userId,
    refreshToken,
    sessionId,
    startedAt,
    lastUsedAt: now,
    userAgent: context.userAgent ?? stored.userAgent,
    ipAddress: context.ipAddress ?? stored.ipAddress,
  });

  return { token, refreshToken, sessionId };
}
