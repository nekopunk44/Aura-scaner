import { Request, Response } from 'express';
import crypto from 'crypto';
import { env } from '../config/env';

const CALLBACK_SCHEME = 'aurascanner';

// GET /auth/vk/login
export function vkLoginPage(req: Request, res: Response): void {
  if (!env.vkAppId) {
    res.status(503).send('<h3>VK login не настроен. Задайте VK_APP_ID в .env</h3>');
    return;
  }

  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/api/auth/vk/callback`;

  const authUrl = new URL('https://oauth.vk.com/authorize');
  authUrl.searchParams.set('client_id', env.vkAppId);
  authUrl.searchParams.set('redirect_uri', callbackUrl);
  authUrl.searchParams.set('scope', 'email');
  authUrl.searchParams.set('response_type', 'token');
  authUrl.searchParams.set('v', '5.131');
  authUrl.searchParams.set('display', 'mobile');

  res.redirect(302, authUrl.toString());
}

// GET /auth/vk/callback
// VK возвращает access_token во fragment (#access_token=...),
// который сервер не видит. Отдаём HTML-страницу, которая читает fragment,
// вызывает /api/auth/social, и редиректит в приложение.
export function vkCallback(req: Request, res: Response): void {
  const nonce = crypto.randomBytes(16).toString('base64');
  const origin = `${req.protocol}://${req.headers.host}`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Content-Security-Policy', `script-src 'nonce-${nonce}'`);
  res.send(`<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Авторизация ВКонтакте</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         min-height:100vh;display:flex;flex-direction:column;align-items:center;
         justify-content:center;background:linear-gradient(160deg,#0f1923 0%,#1a2a3a 50%,#0d2137 100%);
         color:#fff;padding:32px 24px;text-align:center}
    .card{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);
          border-radius:24px;padding:40px 32px;max-width:360px;width:100%}
    .icon{width:72px;height:72px;margin:0 auto 24px;background:rgba(0,119,255,.15);
          border-radius:50%;display:flex;align-items:center;justify-content:center;
          border:2px solid rgba(0,119,255,.35);font-size:28px}
    h1{font-size:20px;font-weight:700;margin-bottom:10px}
    p{font-size:14px;color:rgba(255,255,255,.55);line-height:1.6;margin-bottom:24px}
    #err{color:#ff6b6b;font-size:13px;margin-top:12px;display:none}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">ВК</div>
    <h1>Авторизация ВКонтакте</h1>
    <p id="msg">Обработка данных...</p>
    <div id="err"></div>
  </div>
  <script nonce="${nonce}">
(function () {
  var msg = document.getElementById('msg');
  var err = document.getElementById('err');

  var hash = location.hash.slice(1);
  var params = new URLSearchParams(hash);
  var accessToken = params.get('access_token');
  var email = params.get('email');

  if (!accessToken) {
    msg.textContent = 'Данные не получены. Попробуйте снова.';
    return;
  }

  var body = { provider: 'vk', token: accessToken };
  if (email) body.email = email;

  fetch('${origin}/api/auth/social', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
    .then(function (r) { return r.json(); })
    .then(function (data) {
      if (!data.token) {
        throw new Error(data.message || 'Ошибка авторизации');
      }
      var p = new URLSearchParams({ token: data.token });
      if (data.refreshToken) p.set('refreshToken', data.refreshToken);
      if (data.userId)       p.set('userId', data.userId);
      if (data.email)        p.set('email', data.email);
      if (data.name)         p.set('name', data.name);

      var uri = '${CALLBACK_SCHEME}://oauth2redirect?' + p.toString();
      msg.textContent = 'Возврат в приложение...';

      if (typeof FlutterAuth !== 'undefined') {
        FlutterAuth.postMessage(uri);
      } else {
        window.location.href = uri;
      }
    })
    .catch(function (e) {
      msg.textContent = 'Ошибка авторизации.';
      err.textContent = e.message;
      err.style.display = 'block';
    });
})();
  </script>
</body>
</html>`);
}
