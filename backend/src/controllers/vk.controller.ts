import { Request, Response } from 'express';
import https from 'https';
import crypto from 'crypto';
import { env } from '../config/env';
import { loginOrCreateUserAndIssueCode } from './social.auth.controller';
import { logger } from '../utils/logger';
import { buildAndroidIntentUri, buildOAuthCodeDeepLink } from '../utils/oauth.links';

function base64url(buffer: Buffer): string {
  return buffer
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function pkce(): { verifier: string; challenge: string } {
  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash('sha256').update(verifier).digest());
  return { verifier, challenge };
}

export function vkLoginPage(req: Request, res: Response): void {
  if (!env.vkAppId) {
    res.status(503).send('<h3>VK login не настроен. Задайте VK_APP_ID в .env</h3>');
    return;
  }

  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/vk_id_redirect`;
  const { verifier, challenge } = pkce();
  const state = base64url(Buffer.from(verifier));

  const authUrl = new URL('https://id.vk.com/authorize');
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('client_id', env.vkAppId);
  authUrl.searchParams.set('redirect_uri', callbackUrl);
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('code_challenge', challenge);
  authUrl.searchParams.set('code_challenge_method', 'S256');
  authUrl.searchParams.set('scope', 'email');

  res.redirect(302, authUrl.toString());
}

export function vkCallback(req: Request, res: Response): void {
  const { code, state, error, error_description } = req.query as Record<string, string>;

  if (error || !code || !state) {
    const message = error_description ?? error ?? 'Авторизация отменена';
    res.status(400).send(`<h3>${message}</h3>`);
    return;
  }

  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/vk_id_redirect`;
  const verifier = Buffer.from(state, 'base64').toString('utf-8');

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: callbackUrl,
    code_verifier: verifier,
    client_id: env.vkAppId,
  }).toString();

  const tokenReq = https.request(
    {
      hostname: 'id.vk.com',
      path: '/oauth2/auth',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(body),
      },
    },
    (tokenRes) => {
      let raw = '';
      tokenRes.on('data', (chunk) => (raw += chunk));
      tokenRes.on('end', () => {
        let tokenData: { access_token?: string; error?: string };
        try {
          tokenData = JSON.parse(raw);
        } catch {
          res.status(500).send('<h3>Ошибка разбора ответа VK</h3>');
          return;
        }

        if (!tokenData.access_token) {
          res
            .status(400)
            .send(`<h3>VK не вернул токен: ${tokenData.error ?? 'unknown'}</h3>`);
          return;
        }

        const profileBody =
          `access_token=${encodeURIComponent(tokenData.access_token)}` +
          `&client_id=${encodeURIComponent(env.vkAppId)}`;
        const profileReq = https.request(
          {
            hostname: 'id.vk.com',
            path: '/oauth2/user_info',
            method: 'POST',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Content-Length': Buffer.byteLength(profileBody),
            },
          },
          (profileRes) => {
            let profileRaw = '';
            profileRes.on('data', (chunk) => (profileRaw += chunk));
            profileRes.on('end', () => {
              let profile: {
                user?: {
                  user_id?: string;
                  first_name?: string;
                  last_name?: string;
                };
                error?: string;
              };
              try {
                profile = JSON.parse(profileRaw);
              } catch {
                res.status(500).send('<h3>Ошибка разбора профиля VK</h3>');
                return;
              }

              const vkUser = profile.user;
              if (!vkUser?.user_id) {
                res
                  .status(400)
                  .send(
                    `<h3>Не удалось получить профиль VK: ${profile.error ?? 'unknown'}</h3>`,
                  );
                return;
              }

              const userId = String(vkUser.user_id);
              const name =
                [vkUser.first_name, vkUser.last_name].filter(Boolean).join(' ') ||
                `vk_${userId}`;

              loginOrCreateUserAndIssueCode({
                email: `vk_${userId}@vk.placeholder`,
                name,
                provider: 'vk',
                providerUserId: userId,
                emailVerified: false,
              })
                .then((oneTimeCode) => {
                  logger.info(`[vkCallback] Success: vk_user_id=${userId}`);
                  const deepLink = buildOAuthCodeDeepLink(oneTimeCode);
                  const intentUri = buildAndroidIntentUri(oneTimeCode);

                  res.setHeader('Content-Type', 'text/html; charset=utf-8');
                  res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Авторизация ВКонтакте</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         min-height:100vh;display:flex;align-items:center;justify-content:center;
         background:linear-gradient(160deg,#0f1923,#1a2a3a,#0d2137);
         color:#fff;padding:32px 24px;text-align:center}
    .card{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);
          border-radius:24px;padding:40px 32px;max-width:360px;width:100%}
    .icon{width:72px;height:72px;margin:0 auto 24px;background:rgba(0,119,255,.15);
          border-radius:50%;display:flex;align-items:center;justify-content:center;
          border:2px solid rgba(0,119,255,.35);font-size:26px;font-weight:700}
    h1{font-size:20px;font-weight:700;margin-bottom:10px}
    p{font-size:14px;color:rgba(255,255,255,.55);line-height:1.6;margin-bottom:20px}
    a.btn{display:inline-flex;align-items:center;gap:8px;padding:14px 28px;
          background:#0077FF;color:#fff;text-decoration:none;border-radius:14px;
          font-size:15px;font-weight:600;box-shadow:0 6px 20px rgba(0,119,255,.35)}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">ВК</div>
    <h1>Авторизация выполнена</h1>
    <p>Нажмите кнопку ниже чтобы вернуться в приложение:</p>
    <a id="btn" class="btn" href="${deepLink}">Открыть Aura Scanner</a>
  </div>
  <script>
    var isAndroid = /Android/i.test(navigator.userAgent);
    var target = isAndroid ? ${JSON.stringify(intentUri)} : ${JSON.stringify(deepLink)};
    document.getElementById('btn').href = target;
  </script>
</body>
</html>`);
                })
                .catch((requestError: Error) => {
                  logger.error('[vkCallback] Error issuing OAuth code:', {
                    err: requestError,
                  });
                  res
                    .status(500)
                    .send(`<h3>Ошибка авторизации: ${requestError.message}</h3>`);
                });
            });
          },
        );

        profileReq.on('error', (requestError) => {
          res.status(500).send(`<h3>Ошибка запроса профиля: ${requestError.message}</h3>`);
        });
        profileReq.write(profileBody);
        profileReq.end();
      });
    },
  );

  tokenReq.on('error', (requestError) => {
    res.status(500).send(`<h3>Ошибка обмена кода: ${requestError.message}</h3>`);
  });
  tokenReq.write(body);
  tokenReq.end();
}
