import crypto from 'crypto';

export interface TelegramAuthData {
  id: string | number;
  hash: string;
  auth_date: string | number;
  first_name?: string;
  last_name?: string;
  username?: string;
  photo_url?: string;
}

export function verifyTelegramAuthData(
  data: TelegramAuthData,
  botToken: string,
): boolean {
  if (!botToken) {
    return false;
  }

  const { hash, ...rest } = data;
  const checkString = Object.entries(rest)
    .filter(([, value]) => value !== undefined && value !== null)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  const secretKey = crypto.createHash('sha256').update(botToken).digest();
  const expectedHash = crypto
    .createHmac('sha256', secretKey)
    .update(checkString)
    .digest('hex');

  if (expectedHash !== hash) {
    return false;
  }

  const ageSeconds = Math.floor(Date.now() / 1000) - Number(data.auth_date);
  return Number.isFinite(ageSeconds) && ageSeconds <= 3600;
}
