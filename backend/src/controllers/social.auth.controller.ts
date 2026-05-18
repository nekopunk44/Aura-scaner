import { Request, Response } from 'express';
import https from 'https';
import crypto from 'crypto';
import { User } from '../models/User';
import { signToken, signRefreshToken } from '../utils/jwt';
import { RefreshToken } from '../models/RefreshToken';
import { env } from '../config/env';
import { logger } from '../utils/logger';
import { exchangeInstagramCode } from './telegram.controller';

const CALLBACK_SCHEME = 'aurascanner';

// ──────────────────────────────────────────────────────────────────────────────
// Обмен Google auth code на токены (server-side Web application flow)
// ──────────────────────────────────────────────────────────────────────────────
function exchangeGoogleCode(
  code: string,
  redirectUri: string,
): Promise<{ idToken: string }> {
  return new Promise((resolve, reject) => {
    if (!env.googleClientId || !env.googleClientSecret) {
      reject(new Error('Google OAuth не настроен. Задайте GOOGLE_CLIENT_ID и GOOGLE_CLIENT_SECRET в .env'));
      return;
    }

    const body = new URLSearchParams({
      code,
      client_id: env.googleClientId,
      client_secret: env.googleClientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }).toString();

    const options = {
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let raw = '';
      res.on('data', (chunk) => (raw += chunk));
      res.on('end', () => {
        try {
          const data = JSON.parse(raw) as {
            id_token?: string;
            error?: string;
            error_description?: string;
          };
          if (!data.id_token) {
            reject(new Error(data.error_description ?? data.error ?? 'Google не вернул id_token'));
            return;
          }
          resolve({ idToken: data.id_token });
        } catch {
          reject(new Error('Ошибка разбора ответа Google'));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// GET /auth/google/callback — принимает code от Google, выдаёт JWT через deep link
// ──────────────────────────────────────────────────────────────────────────────
export async function googleCallback(req: Request, res: Response): Promise<void> {
  const { code, error } = req.query as Record<string, string | undefined>;

  if (error) {
    logger.warn(`[googleCallback] OAuth error: ${error}`);
    res.redirect(302, `${CALLBACK_SCHEME}://oauth2redirect?error=${encodeURIComponent(error)}`);
    return;
  }

  if (!code) {
    res.status(400).send('<h3>Отсутствует код авторизации</h3>');
    return;
  }

  const redirectUri = `${req.protocol}://${req.headers.host}/api/auth/google/callback`;

  try {
    const { idToken } = await exchangeGoogleCode(code, redirectUri);
    const googlePayload = await verifyGoogleToken(idToken);

    let user = await User.findOne({ email: googlePayload.email });
    if (!user) {
      const randomPassword = crypto.randomBytes(32).toString('hex');
      user = await User.create({
        email: googlePayload.email,
        name: googlePayload.name,
        password: randomPassword,
      });
    }

    const jwtToken = signToken(String(user._id));
    const refreshToken = signRefreshToken(String(user._id));
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await RefreshToken.create({ userId: user._id, token: refreshToken, expiresAt });

    const params = new URLSearchParams({
      token: jwtToken,
      refreshToken,
      userId: String(user._id),
      email: user.email,
      name: user.name ?? '',
    });

    logger.info(`[googleCallback] Success: email=${user.email}`);
    const deepLink = `${CALLBACK_SCHEME}://oauth2redirect?${params.toString()}`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(buildDeepLinkPage(deepLink));
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Ошибка авторизации Google';
    logger.error('[googleCallback] Error:', { err });
    const deepLink = `${CALLBACK_SCHEME}://oauth2redirect?error=${encodeURIComponent(message)}`;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(buildDeepLinkPage(deepLink, message));
  }
}

function buildDeepLinkPage(deepLink: string, errorMsg?: string): string {
  return `<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${errorMsg ? 'Ошибка' : 'Возврат в приложение'}</title>
  <style>
    body{font-family:sans-serif;display:flex;flex-direction:column;align-items:center;
         justify-content:center;height:100vh;margin:0;background:#f5f5f5;color:#333;}
    p{text-align:center;padding:0 24px;}
  </style>
</head>
<body>
  <p>${errorMsg ? `Ошибка: ${errorMsg}` : 'Авторизация выполнена. Возврат в приложение…'}</p>
  <script>
    window.location.href = ${JSON.stringify(deepLink)};
  </script>
</body>
</html>`;
}

// ──────────────────────────────────────────────────────────────────────────────
// Вспомогательная функция: верификация Google id_token через tokeninfo endpoint
// ──────────────────────────────────────────────────────────────────────────────
function verifyGoogleToken(idToken: string): Promise<{ email: string; name: string }> {
  return new Promise((resolve, reject) => {
    const url = `https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=${encodeURIComponent(idToken)}`;
    https
      .get(url, (res) => {
        let raw = '';
        res.on('data', (chunk) => (raw += chunk));
        res.on('end', () => {
          try {
            const payload = JSON.parse(raw) as Record<string, string>;
            if (payload.error_description || !payload.email) {
              reject(new Error(payload.error_description ?? 'Invalid Google token'));
              return;
            }
            resolve({
              email: payload.email,
              name: payload.name ?? payload.email.split('@')[0],
            });
          } catch {
            reject(new Error('Failed to parse Google tokeninfo response'));
          }
        });
      })
      .on('error', reject);
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// Верификация VK access_token через users.get API
// ──────────────────────────────────────────────────────────────────────────────
function verifyVkToken(accessToken: string): Promise<{ vkId: string; name: string }> {
  return new Promise((resolve, reject) => {
    const url = `https://api.vk.com/method/users.get?access_token=${encodeURIComponent(accessToken)}&v=5.131`;
    https
      .get(url, (res) => {
        let raw = '';
        res.on('data', (chunk) => (raw += chunk));
        res.on('end', () => {
          try {
            const payload = JSON.parse(raw) as {
              error?: { error_msg: string };
              response?: Array<{ id: number; first_name: string; last_name: string }>;
            };
            if (payload.error || !payload.response || payload.response.length === 0) {
              reject(new Error(payload.error?.error_msg ?? 'Invalid VK token'));
              return;
            }
            const vkUser = payload.response[0];
            resolve({
              vkId: String(vkUser.id),
              name: `${vkUser.first_name} ${vkUser.last_name}`.trim(),
            });
          } catch {
            reject(new Error('Failed to parse VK API response'));
          }
        });
      })
      .on('error', reject);
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// Верификация Telegram Login Widget hash по алгоритму Telegram
// ──────────────────────────────────────────────────────────────────────────────
interface TelegramAuthData {
  id: string | number;
  hash: string;
  auth_date: string | number;
  first_name?: string;
  last_name?: string;
  username?: string;
}

function verifyTelegramHash(data: TelegramAuthData): boolean {
  // Если токен не настроен — пропускаем верификацию (режим разработки)
  if (!env.telegramBotToken) {
    return true;
  }

  const { hash, ...rest } = data;

  // Формируем check_string: отсортированные "key=value" через \n
  const checkString = Object.entries(rest)
    .filter(([, v]) => v !== undefined && v !== null)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}=${v}`)
    .join('\n');

  // secret_key = SHA256(bot_token)
  const secretKey = crypto.createHash('sha256').update(env.telegramBotToken).digest();

  // expected_hash = HMAC-SHA256(check_string, secret_key)
  const expectedHash = crypto
    .createHmac('sha256', secretKey)
    .update(checkString)
    .digest('hex');

  return expectedHash === hash;
}

// ──────────────────────────────────────────────────────────────────────────────
// POST /auth/social
//
// Body для google:
//   { provider: 'google', token: '<id_token>', name?: string }
//
// Body для vk:
//   { provider: 'vk', token: '<access_token>', email?: string, name?: string }
//
// Body для telegram:
//   { provider: 'telegram', token: '<any>', id, hash, auth_date, first_name?, last_name?, username? }
//
// Body для instagram:
//   { provider: 'instagram', token: '<code>', email: string, name?: string }
// ──────────────────────────────────────────────────────────────────────────────
export async function socialLogin(req: Request, res: Response): Promise<void> {
  const {
    provider,
    token,
    email: bodyEmail,
    name: bodyName,
    // Telegram-specific fields
    id: tgId,
    hash: tgHash,
    auth_date: tgAuthDate,
    first_name: tgFirstName,
    last_name: tgLastName,
    username: tgUsername,
  } = req.body as {
    provider?: string;
    token?: string;
    email?: string;
    name?: string;
    id?: string | number;
    hash?: string;
    auth_date?: string | number;
    first_name?: string;
    last_name?: string;
    username?: string;
  };

  // ── Валидация входных данных ─────────────────────────────────────────────
  if (!provider) {
    res.status(400).json({ message: 'Поле provider обязательно' });
    return;
  }

  const allowedProviders = ['google', 'vk', 'telegram', 'instagram'];
  if (!allowedProviders.includes(provider)) {
    res.status(400).json({ message: `Неизвестный провайдер: ${provider}` });
    return;
  }

  if (provider !== 'telegram' && !token) {
    res.status(400).json({ message: 'Поле token обязательно' });
    return;
  }

  let verifiedEmail: string;
  let verifiedName: string;

  try {
    if (provider === 'google') {
      // ── Google: верифицируем id_token через googleapis ────────────────────
      const googlePayload = await verifyGoogleToken(token!);
      verifiedEmail = googlePayload.email;
      verifiedName = bodyName ?? googlePayload.name;

    } else if (provider === 'vk') {
      // ── VK: серверная верификация через users.get API ─────────────────────
      // Email у VK нельзя получить через API без явного разрешения пользователя,
      // поэтому принимаем email из тела или генерируем placeholder по vkId
      const vkPayload = await verifyVkToken(token!);
      verifiedEmail = bodyEmail
        ? bodyEmail.toLowerCase().trim()
        : `vk_${vkPayload.vkId}@vk.placeholder`;
      verifiedName = bodyName ?? vkPayload.name;

    } else if (provider === 'telegram') {
      // ── Telegram: HMAC-SHA256 верификация по алгоритму Telegram Login Widget
      if (!tgId || !tgHash || !tgAuthDate) {
        res.status(400).json({ message: 'Для Telegram необходимы поля id, hash, auth_date' });
        return;
      }

      const tgData: TelegramAuthData = {
        id: tgId,
        hash: tgHash,
        auth_date: tgAuthDate,
        ...(tgFirstName && { first_name: tgFirstName }),
        ...(tgLastName && { last_name: tgLastName }),
        ...(tgUsername && { username: tgUsername }),
      };

      if (!verifyTelegramHash(tgData)) {
        res.status(401).json({ message: 'Недействительная подпись Telegram' });
        return;
      }

      // Telegram не даёт email — принимаем из тела или генерируем placeholder
      verifiedEmail = bodyEmail
        ? bodyEmail.toLowerCase().trim()
        : `tg_${tgId}@telegram.placeholder`;

      const fullName = [tgFirstName, tgLastName].filter(Boolean).join(' ');
      verifiedName = bodyName ?? (fullName || (tgUsername ?? String(tgId)));

    } else {
      // ── Instagram: обмениваем code на access_token через сервер ──────────
      const redirectUri = 'com.example.scanner_ap:/oauth2redirect';
      const igProfile = await exchangeInstagramCode(token!, redirectUri);
      verifiedEmail = bodyEmail
        ? bodyEmail.toLowerCase().trim()
        : `ig_${igProfile.userId}@instagram.placeholder`;
      verifiedName = bodyName ?? igProfile.username;
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Ошибка верификации токена';
    res.status(401).json({ message });
    return;
  }

  // ── Найти или создать пользователя ──────────────────────────────────────
  try {
    let user = await User.findOne({ email: verifiedEmail });

    if (!user) {
      // Генерируем случайный пароль — пользователь всё равно будет логиниться
      // через OAuth, прямой пароль ему не нужен
      const randomPassword = crypto.randomBytes(32).toString('hex');
      user = await User.create({
        email: verifiedEmail,
        name: verifiedName,
        password: randomPassword,
      });
    }

    const jwtToken = signToken(String(user._id));
    const refreshToken = signRefreshToken(String(user._id));
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    await RefreshToken.create({ userId: user._id, token: refreshToken, expiresAt });

    res.json({
      token: jwtToken,
      refreshToken,
      user: { id: user._id, email: user.email, name: user.name },
    });
  } catch (err) {
    logger.error('[socialLogin] DB error:', { err });
    res.status(500).json({ message: 'Внутренняя ошибка сервера' });
  }
}
