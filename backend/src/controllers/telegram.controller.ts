import { Request, Response } from 'express';
import https from 'https';
import crypto from 'crypto';
import { env } from '../config/env';
import { logger } from '../utils/logger';

const CALLBACK_SCHEME = 'aurascanner';

// GET /auth/telegram/login
// Отдаёт HTML-страницу с Telegram Login Widget.
// Flutter открывает её через FlutterWebAuth2.
export function telegramLoginPage(_req: Request, res: Response): void {
  if (!env.telegramBotUsername) {
    res.status(503).send(
      '<h3>Telegram login не настроен. Задайте TELEGRAM_BOT_USERNAME в .env</h3>',
    );
    return;
  }

  const callbackUrl = `${_req.protocol}://${_req.headers.host}/api/auth/telegram/callback`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Вход через Telegram</title>
  <style>
    body { font-family: sans-serif; display: flex; flex-direction: column;
           align-items: center; justify-content: center; height: 100vh;
           margin: 0; background: #f5f5f5; }
    h2 { color: #333; margin-bottom: 24px; }
  </style>
</head>
<body>
  <h2>Вход через Telegram</h2>
  <script async src="https://telegram.org/js/telegram-widget.js?22"
    data-telegram-login="${env.telegramBotUsername}"
    data-size="large"
    data-auth-url="${callbackUrl}"
    data-request-access="write">
  </script>
</body>
</html>`);
}

// GET /auth/telegram/callback
// Telegram вызывает этот URL после авторизации пользователя.
// Верифицирует hash, затем делает redirect в приложение через deep link.
export function telegramCallback(req: Request, res: Response): void {
  const { id, hash, auth_date, first_name, last_name, username, photo_url } =
    req.query as Record<string, string | undefined>;

  if (!id || !hash || !auth_date) {
    res.status(400).send('<h3>Недостаточно данных от Telegram</h3>');
    return;
  }

  // Верификация hash
  if (env.telegramBotToken) {
    const fields: Record<string, string> = { id, auth_date };
    if (first_name) fields['first_name'] = first_name;
    if (last_name) fields['last_name'] = last_name;
    if (username) fields['username'] = username;
    if (photo_url) fields['photo_url'] = photo_url;

    const checkString = Object.entries(fields)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([k, v]) => `${k}=${v}`)
      .join('\n');

    const secretKey = crypto.createHash('sha256').update(env.telegramBotToken).digest();
    const expectedHash = crypto.createHmac('sha256', secretKey).update(checkString).digest('hex');

    if (expectedHash !== hash) {
      logger.warn('[telegramCallback] Invalid hash');
      res.status(401).send('<h3>Недействительная подпись Telegram</h3>');
      return;
    }

    // auth_date не должна быть старше 1 часа
    const age = Math.floor(Date.now() / 1000) - parseInt(auth_date, 10);
    if (age > 3600) {
      res.status(401).send('<h3>Данные авторизации устарели. Попробуйте снова.</h3>');
      return;
    }
  }

  // Собираем параметры для redirect в приложение
  const params = new URLSearchParams({ id, hash, auth_date });
  if (first_name) params.set('first_name', first_name);
  if (last_name) params.set('last_name', last_name);
  if (username) params.set('username', username);

  const deepLink = `${CALLBACK_SCHEME}:/oauth2redirect?${params.toString()}`;
  logger.info(`[telegramCallback] Redirecting to app: tg_id=${id}`);
  res.redirect(302, deepLink);
}

// Вспомогательная функция для обмена Instagram code → access_token
// Используется в social.auth.controller.ts
export function exchangeInstagramCode(
  code: string,
  redirectUri: string,
): Promise<{ userId: string; username: string }> {
  return new Promise((resolve, reject) => {
    if (!env.instagramAppId || !env.instagramAppSecret) {
      reject(new Error('Instagram не настроен. Задайте INSTAGRAM_APP_ID и INSTAGRAM_APP_SECRET в .env'));
      return;
    }

    const body = new URLSearchParams({
      client_id: env.instagramAppId,
      client_secret: env.instagramAppSecret,
      grant_type: 'authorization_code',
      redirect_uri: redirectUri,
      code,
    }).toString();

    const options = {
      hostname: 'api.instagram.com',
      path: '/oauth/access_token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const tokenReq = https.request(options, (tokenRes) => {
      let raw = '';
      tokenRes.on('data', (chunk) => (raw += chunk));
      tokenRes.on('end', () => {
        try {
          const data = JSON.parse(raw) as {
            access_token?: string;
            user_id?: number;
            error_message?: string;
          };

          if (!data.access_token || !data.user_id) {
            reject(new Error(data.error_message ?? 'Instagram не вернул токен'));
            return;
          }

          // Получаем username через Graph API
          const profileUrl =
            `https://graph.instagram.com/me?fields=id,username&access_token=${encodeURIComponent(data.access_token)}`;
          https
            .get(profileUrl, (profileRes) => {
              let profileRaw = '';
              profileRes.on('data', (c) => (profileRaw += c));
              profileRes.on('end', () => {
                try {
                  const profile = JSON.parse(profileRaw) as {
                    id?: string;
                    username?: string;
                    error?: { message: string };
                  };
                  if (profile.error || !profile.id) {
                    reject(new Error(profile.error?.message ?? 'Ошибка получения профиля Instagram'));
                    return;
                  }
                  resolve({
                    userId: profile.id,
                    username: profile.username ?? `ig_${profile.id}`,
                  });
                } catch {
                  reject(new Error('Ошибка разбора профиля Instagram'));
                }
              });
            })
            .on('error', reject);
        } catch {
          reject(new Error('Ошибка разбора ответа Instagram'));
        }
      });
    });

    tokenReq.on('error', reject);
    tokenReq.write(body);
    tokenReq.end();
  });
}
