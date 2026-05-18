import { Request, Response } from 'express';
import https from 'https';
import crypto from 'crypto';
import { env } from '../config/env';
import { logger } from '../utils/logger';

const CALLBACK_SCHEME = 'aurascanner';

// GET /auth/telegram/login
// Перенаправляет напрямую на oauth.telegram.org, минуя промежуточную страницу с виджетом.
// bot_id — числовой ID бота, первая часть TELEGRAM_BOT_TOKEN до двоеточия.
export function telegramLoginPage(req: Request, res: Response): void {
  if (!env.telegramBotToken) {
    res.status(503).send(
      '<h3>Telegram login не настроен. Задайте TELEGRAM_BOT_TOKEN в .env</h3>',
    );
    return;
  }

  const botId = env.telegramBotToken.split(':')[0];
  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/api/auth/telegram/callback`;

  const authUrl = new URL('https://oauth.telegram.org/auth');
  authUrl.searchParams.set('bot_id', botId);
  authUrl.searchParams.set('origin', origin);
  authUrl.searchParams.set('request_access', 'write');
  authUrl.searchParams.set('return_to', callbackUrl);

  res.redirect(302, authUrl.toString());
}

// GET /auth/telegram/callback
// Поддерживает три формата ответа от Telegram:
//   1. Login Widget:       ?id=...&hash=...&auth_date=...
//   2. oauth.telegram.org: ?tgAuthResult=BASE64_JSON  (query)
//   3. oauth.telegram.org: #tgAuthResult=BASE64_JSON  (fragment — сервер не видит,
//      поэтому отдаём JS-страницу, которая читает fragment и делает редирект)
export function telegramCallback(req: Request, res: Response): void {
  let { id, hash, auth_date, first_name, last_name, username, photo_url } =
    req.query as Record<string, string | undefined>;

  // Формат 2: tgAuthResult как query-параметр
  const tgAuthResult = req.query['tgAuthResult'] as string | undefined;
  if (tgAuthResult) {
    try {
      const b64 = tgAuthResult.replace(/-/g, '+').replace(/_/g, '/');
      const decoded = JSON.parse(
        Buffer.from(b64, 'base64').toString('utf-8'),
      ) as Record<string, unknown>;
      id         = decoded['id']?.toString();
      hash       = decoded['hash'] as string | undefined;
      auth_date  = decoded['auth_date']?.toString();
      first_name = decoded['first_name'] as string | undefined;
      last_name  = decoded['last_name']  as string | undefined;
      username   = decoded['username']   as string | undefined;
      photo_url  = decoded['photo_url']  as string | undefined;
    } catch {
      logger.warn('[telegramCallback] Failed to decode tgAuthResult query param');
    }
  }

  // Формат 3: данных нет в query → возможно, tgAuthResult в fragment или
  // oauth.telegram.org вернул пустой callback. Отдаём JS-страницу для диагностики и редиректа.
  if (!id || !hash || !auth_date) {
    logger.warn('[telegramCallback] No params in query. url=%s', req.url);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.send(`<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Авторизация Telegram</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:sans-serif;background:#0f1923;color:#fff;
         display:flex;flex-direction:column;align-items:center;
         justify-content:center;min-height:100vh;padding:24px;text-align:center}
    #btn{display:none;margin-top:24px;padding:14px 32px;background:#2CA5E0;
         color:#fff;text-decoration:none;border-radius:14px;font-size:16px;font-weight:600}
    pre{background:rgba(255,255,255,.08);padding:12px;border-radius:8px;margin-top:16px;
        font-size:11px;text-align:left;max-width:100%;word-break:break-all;white-space:pre-wrap}
  </style>
</head>
<body>
<p id="status">Обработка данных Telegram...</p>
<a id="btn" href="#">Открыть приложение</a>
<pre id="debug"></pre>
<script>
(function () {
  var dbg = document.getElementById('debug');
  var st  = document.getElementById('status');
  var btn = document.getElementById('btn');

  function getParam(str, key) { return new URLSearchParams(str).get(key); }

  var raw = getParam(location.search.slice(1), 'tgAuthResult')
         || getParam(location.hash.slice(1),   'tgAuthResult');

  dbg.textContent = 'search: ' + location.search + '\\nhash: ' + location.hash.substring(0,40);

  if (!raw) {
    st.textContent = 'Данные не найдены. Попробуйте снова.';
    return;
  }

  try {
    var b64 = raw.replace(/-/g, '+').replace(/_/g, '/');
    while (b64.length % 4) b64 += '=';
    var d = JSON.parse(atob(b64));

    var p = new URLSearchParams();
    p.set('id',        String(d.id));
    p.set('hash',      d.hash);
    p.set('auth_date', String(d.auth_date));
    if (d.first_name) p.set('first_name', d.first_name);
    if (d.last_name)  p.set('last_name',  d.last_name);
    if (d.username)   p.set('username',   d.username);

    var uri = 'aurascanner://oauth2redirect?' + p.toString();

    btn.href = uri;
    btn.style.display = 'inline-block';
    st.textContent = 'Возврат в приложение...';

    // Самый надёжный способ: JS channel напрямую в Flutter
    if (typeof FlutterAuth !== 'undefined') {
      FlutterAuth.postMessage(uri);
    } else {
      window.location.href = uri;
    }
  } catch (e) {
    st.textContent = 'Ошибка разбора: ' + e.message;
  }
})();
</script>
</body>
</html>`);
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

  const deepLink = `${CALLBACK_SCHEME}://oauth2redirect?${params.toString()}`;
  const afterScheme = deepLink.replace(/^aurascanner:\/\//, '');
  const intentUri = `intent://${afterScheme}#Intent;scheme=aurascanner;package=com.example.scanner_ap;end`;

  logger.info(`[telegramCallback] Redirecting to app: tg_id=${id}`);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Авторизация выполнена</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         min-height:100vh;display:flex;flex-direction:column;align-items:center;
         justify-content:center;background:linear-gradient(160deg,#0f1923 0%,#1a2a3a 50%,#0d2137 100%);
         color:#fff;padding:32px 24px;text-align:center}
    .card{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);
          border-radius:24px;padding:40px 32px;max-width:360px;width:100%}
    .check-wrap{width:80px;height:80px;margin:0 auto 28px;
                background:rgba(44,165,224,.15);border-radius:50%;
                display:flex;align-items:center;justify-content:center;
                border:2px solid rgba(44,165,224,.35)}
    .check-wrap svg{width:38px;height:38px}
    h1{font-size:20px;font-weight:700;letter-spacing:.2px;margin-bottom:10px}
    p{font-size:14px;color:rgba(255,255,255,.55);line-height:1.6;margin-bottom:32px}
    a.btn{display:flex;align-items:center;justify-content:center;gap:10px;
          padding:15px 28px;background:#2CA5E0;color:#fff;text-decoration:none;
          border-radius:14px;font-size:15px;font-weight:600;
          box-shadow:0 6px 24px rgba(44,165,224,.35);transition:opacity .15s}
    a.btn:active{opacity:.85}
    .tg-icon{width:20px;height:20px;fill:#fff;flex-shrink:0}
  </style>
</head>
<body>
  <div class="card">
    <div class="check-wrap">
      <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
        <circle cx="12" cy="12" r="11" stroke="#2CA5E0" stroke-width="1.5"/>
        <path d="M7 12.5l3.5 3.5 6.5-7" stroke="#2CA5E0" stroke-width="2"
              stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    </div>
    <h1>Авторизация выполнена</h1>
    <p>Вы успешно вошли через Telegram.<br>Возврат в приложение...</p>
    <a class="btn" id="btn" href="${deepLink}">
      <svg class="tg-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="M22 2L11 13M22 2L15 22l-4-9-9-4 20-7z"/>
      </svg>
      Открыть приложение
    </a>
  </div>
  <script>
    var isAndroid = /Android/i.test(navigator.userAgent);
    var target = isAndroid ? ${JSON.stringify(intentUri)} : ${JSON.stringify(deepLink)};
    setTimeout(function(){ window.location.href = target; }, 600);
    document.getElementById('btn').href = target;
  </script>
</body>
</html>`);
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
