import { Request, Response } from 'express';
import https from 'https';
import crypto from 'crypto';
import { env } from '../config/env';

const CALLBACK_SCHEME = 'aurascanner';

function base64url(buf: Buffer): string {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function pkce(): { verifier: string; challenge: string } {
  const verifier = base64url(crypto.randomBytes(32));
  const challenge = base64url(crypto.createHash('sha256').update(verifier).digest());
  return { verifier, challenge };
}

// GET /auth/vk/login
export function vkLoginPage(req: Request, res: Response): void {
  if (!env.vkAppId) {
    res.status(503).send('<h3>VK login не настроен. Задайте VK_APP_ID в .env</h3>');
    return;
  }

  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/vk_id_redirect`;
  const { verifier, challenge } = pkce();

  // Передаём verifier в state (base64url) — PKCE не требует секретности verifier
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

// GET /auth/vk/callback?code=...&state=...
export function vkCallback(req: Request, res: Response): void {
  const { code, state, error, error_description } = req.query as Record<string, string>;

  if (error || !code || !state) {
    const msg = error_description ?? error ?? 'Авторизация отменена';
    res.status(400).send(`<h3>${msg}</h3>`);
    return;
  }

  const origin = `${req.protocol}://${req.headers.host}`;
  const callbackUrl = `${origin}/vk_id_redirect`;

  // Восстанавливаем verifier из state
  const verifier = Buffer.from(state, 'base64').toString('utf-8');

  // Обмениваем code на access_token через id.vk.com/oauth2/auth
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: callbackUrl,
    code_verifier: verifier,
    client_id: env.vkAppId,
  }).toString();

  const options = {
    hostname: 'id.vk.com',
    path: '/oauth2/auth',
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
      let tokenData: { access_token?: string; email?: string; error?: string };
      try {
        tokenData = JSON.parse(raw);
      } catch {
        res.status(500).send('<h3>Ошибка разбора ответа VK</h3>');
        return;
      }

      if (!tokenData.access_token) {
        res.status(400).send(`<h3>VK не вернул токен: ${tokenData.error ?? 'unknown'}</h3>`);
        return;
      }

      // Получаем профиль пользователя
      const profileUrl = 'https://id.vk.com/oauth2/user_info';
      const profileBody = `access_token=${encodeURIComponent(tokenData.access_token)}&client_id=${encodeURIComponent(env.vkAppId)}`;
      const profileOpts = {
        hostname: 'id.vk.com',
        path: '/oauth2/user_info',
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(profileBody),
        },
      };

      const profileReq = https.request(profileOpts, (profileRes) => {
        let profileRaw = '';
        profileRes.on('data', (c) => (profileRaw += c));
        profileRes.on('end', () => {
          let profile: { user?: { user_id?: string; first_name?: string; last_name?: string; email?: string }; error?: string };
          try {
            profile = JSON.parse(profileRaw);
          } catch {
            res.status(500).send('<h3>Ошибка разбора профиля VK</h3>');
            return;
          }

          const vkUser = profile.user;
          if (!vkUser?.user_id) {
            res.status(400).send(`<h3>Не удалось получить профиль VK: ${profile.error ?? 'unknown'}</h3>`);
            return;
          }

          const email = tokenData.email ?? vkUser.email
            ?? `vk_${vkUser.user_id}@vk.placeholder`;
          const name = [vkUser.first_name, vkUser.last_name].filter(Boolean).join(' ') || `vk_${vkUser.user_id}`;

          // Вызываем socialLogin через внутренний fetch не доступен — делаем прямой запрос
          const socialBody = JSON.stringify({
            provider: 'vk',
            token: tokenData.access_token,
            email,
            name,
          });

          const socialOpts = {
            hostname: req.hostname,
            port: (req.socket as { localPort?: number }).localPort ?? 3000,
            path: '/api/auth/social',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(socialBody),
            },
          };

          const makeDeepLink = (jwtToken: string, refreshToken?: string, userId?: string, userEmail?: string, userName?: string) => {
            const p = new URLSearchParams({ token: jwtToken });
            if (refreshToken) p.set('refreshToken', refreshToken);
            if (userId)       p.set('userId', userId);
            if (userEmail)    p.set('email', userEmail);
            if (userName)     p.set('name', userName);
            return `${CALLBACK_SCHEME}://oauth2redirect?${p.toString()}`;
          };

          const nonce = crypto.randomBytes(16).toString('base64');
          const serverOrigin = `${req.protocol}://${req.headers.host}`;

          // Отдаём HTML с JS, который вызывает /api/auth/social и редиректит в приложение
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
    #err{color:#ff6b6b;font-size:13px;margin-top:12px;display:none}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">ВК</div>
    <h1>Авторизация выполнена</h1>
    <p id="msg">Открываем приложение...</p>
    <a id="btn" class="btn" href="#" style="display:none">Открыть Aura Scanner</a>
    <div id="err"></div>
  </div>
  <script nonce="${nonce}">
(function(){
  var msg = document.getElementById('msg');
  var btn = document.getElementById('btn');
  var err = document.getElementById('err');
  fetch('${serverOrigin}/api/auth/social', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({provider:'vk', token:${JSON.stringify(tokenData.access_token)}, email:${JSON.stringify(email)}, name:${JSON.stringify(name)}})
  })
  .then(function(r){return r.json();})
  .then(function(data){
    if(!data.token){throw new Error(data.message||'Ошибка авторизации');}
    var p = new URLSearchParams({token:data.token});
    if(data.refreshToken) p.set('refreshToken',data.refreshToken);
    if(data.userId) p.set('userId',data.userId);
    if(data.email) p.set('email',data.email);
    if(data.name) p.set('name',data.name);
    var params = p.toString();
    var uri = '${CALLBACK_SCHEME}://oauth2redirect?'+params;
    var intentUri = 'intent://oauth2redirect?'+params+'#Intent;scheme=${CALLBACK_SCHEME};package=com.example.scanner_ap;end';
    btn.href = intentUri;
    btn.style.display = 'inline-flex';
    msg.textContent = 'Нажмите кнопку ниже чтобы вернуться в приложение:';
    if(typeof FlutterAuth!=='undefined'){
      FlutterAuth.postMessage(uri);
    }
  })
  .catch(function(e){
    msg.textContent='Ошибка авторизации.';
    err.textContent=e.message;
    err.style.display='block';
  });
})();
  </script>
</body>
</html>`);
        });
      });

      profileReq.on('error', (e) => res.status(500).send(`<h3>Ошибка запроса профиля: ${e.message}</h3>`));
      profileReq.write(profileBody);
      profileReq.end();
    });
  });

  tokenReq.on('error', (e) => res.status(500).send(`<h3>Ошибка обмена кода: ${e.message}</h3>`));
  tokenReq.write(body);
  tokenReq.end();
}
