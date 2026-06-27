import { Request, Response } from 'express';
import fs from 'fs';
import https from 'https';
import http from 'http';
import path from 'path';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { IUser, User } from '../models/User';
import { OAuthCode } from '../models/OAuthCode';
import { env } from '../config/env';
import { logger } from '../utils/logger';
import { exchangeInstagramCode } from './telegram.controller';
import {
  buildInstagramRedirectUri,
  buildOAuthCodeDeepLink,
  buildOAuthErrorDeepLink,
} from '../utils/oauth.links';
import {
  getRequestSessionContext,
  issueSessionTokens,
  SessionContext,
} from '../utils/sessionTokens';
import { TelegramAuthData, verifyTelegramAuthData } from '../utils/telegramAuth';
import type { AuthRequest } from '../middleware/auth.middleware';

const OAUTH_CODE_TTL_MS = 5 * 60 * 1000;

/** Скачивает внешний аватар (Telegram / Google CDN) и сохраняет локально.
 *  Возвращает путь вида `/uploads/avatars/xxx.jpg` или undefined при ошибке. */
async function downloadExternalAvatar(
  url: string,
  userId: string,
  depth = 0,
): Promise<string | undefined> {
  if (depth > 3) return undefined;
  return new Promise((resolve) => {
    try {
      const filename = `social_${userId}_${Date.now()}.jpg`;
      const dir = path.join(__dirname, '../../uploads/avatars');
      fs.mkdirSync(dir, { recursive: true });
      const filePath = path.join(dir, filename);
      const file = fs.createWriteStream(filePath);
      const cleanup = () => { try { file.close(); fs.unlinkSync(filePath); } catch {} };

      const transport = url.startsWith('https') ? https : http;
      const req = transport.get(
        url,
        { headers: { 'User-Agent': 'Mozilla/5.0 (compatible; AuraBot/1.0)' } },
        (res) => {
          if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            cleanup();
            downloadExternalAvatar(res.headers.location, userId, depth + 1).then(resolve);
            return;
          }
          if (!res.statusCode || res.statusCode !== 200) {
            cleanup();
            resolve(undefined);
            return;
          }
          res.pipe(file);
          file.on('finish', () => { file.close(); resolve(`/uploads/avatars/${filename}`); });
          file.on('error', () => { cleanup(); resolve(undefined); });
        },
      );
      req.setTimeout(8000, () => { req.destroy(); cleanup(); resolve(undefined); });
      req.on('error', () => { cleanup(); resolve(undefined); });
    } catch {
      resolve(undefined);
    }
  });
}

type SocialProvider = 'google' | 'apple' | 'vk' | 'telegram' | 'instagram';
type SocialProviderField =
  | 'googleSub'
  | 'appleSub'
  | 'vkUserId'
  | 'telegramId'
  | 'instagramUserId';

interface SocialIdentity {
  provider: SocialProvider;
  providerUserId: string;
  email: string;
  emailVerified: boolean;
  name: string;
  avatarUrl?: string;
}

export async function createOAuthCode(params: {
  userId: string;
  token: string;
  refreshToken: string;
  sessionId: string;
  email: string;
  name: string;
}): Promise<string> {
  const code = crypto.randomBytes(32).toString('hex');
  await OAuthCode.create({
    code,
    userId: params.userId,
    token: params.token,
    refreshToken: params.refreshToken,
    sessionId: params.sessionId,
    email: params.email,
    name: params.name,
    expiresAt: new Date(Date.now() + OAUTH_CODE_TTL_MS),
  });
  return code;
}

function getProviderField(provider: SocialProvider): SocialProviderField {
  switch (provider) {
    case 'google':
      return 'googleSub';
    case 'apple':
      return 'appleSub';
    case 'vk':
      return 'vkUserId';
    case 'telegram':
      return 'telegramId';
    case 'instagram':
      return 'instagramUserId';
  }
}

/** Если URL внешний — скачивает локально. Иначе возвращает как есть. */
export async function resolveAvatarUrl(
  url: string | undefined,
  providerUserId: string,
): Promise<string | undefined> {
  if (!url) return undefined;
  if (url.startsWith('/')) return url; // already local
  const local = await downloadExternalAvatar(url, providerUserId);
  return local ?? url; // fallback to original URL if download fails
}

async function findOrCreateSocialUser(identity: SocialIdentity): Promise<IUser> {
  const identityField = getProviderField(identity.provider);
  const canLinkByDeterministicPlaceholder =
    !identity.emailVerified && identity.email.endsWith('.placeholder');

  const resolvedAvatar = await resolveAvatarUrl(identity.avatarUrl, identity.providerUserId);

  let user = await User.findOne({ [identityField]: identity.providerUserId });
  if (user) {
    let changed = false;
    if (
      identity.emailVerified &&
      user.email.endsWith('.placeholder') &&
      user.email !== identity.email
    ) {
      user.email = identity.email;
      changed = true;
    }
    // Обновляем аватар если: нет локального аватара или пришёл новый локальный
    const hasLocalAvatar = user.avatarUrl?.startsWith('/');
    if (resolvedAvatar && (!hasLocalAvatar || resolvedAvatar.startsWith('/'))) {
      if (user.avatarUrl !== resolvedAvatar) {
        user.avatarUrl = resolvedAvatar;
        changed = true;
      }
    }
    if (user.authProvider !== identity.provider) {
      user.authProvider = identity.provider;
      changed = true;
    }
    if (changed) {
      await user.save();
    }
    return user;
  }

  if (identity.emailVerified || canLinkByDeterministicPlaceholder) {
    user = await User.findOne({ email: identity.email });
    if (user) {
      const currentValue = user.get(identityField) as string | undefined;
      if (currentValue && currentValue !== identity.providerUserId) {
        throw new Error(`Provider ${identity.provider} already linked to another identity`);
      }
      user.set(identityField, identity.providerUserId);
      user.authProvider = identity.provider;
      if (resolvedAvatar) {
        user.avatarUrl = resolvedAvatar;
      }
      await user.save();
      return user;
    }
  }

  const randomPassword = crypto.randomBytes(32).toString('hex');
  return User.create({
    email: identity.email,
    name: identity.name,
    password: randomPassword,
    [identityField]: identity.providerUserId,
    authProvider: identity.provider,
    ...(resolvedAvatar && { avatarUrl: resolvedAvatar }),
  });
}

async function issueTokensForUser(
  user: IUser,
  sessionContext: SessionContext = {},
): Promise<{
  token: string;
  refreshToken: string;
  sessionId: string;
}> {
  return issueSessionTokens(user._id, sessionContext);
}

export async function loginOrCreateUserAndIssueCode(params: {
  email: string;
  name: string;
  provider?: SocialProvider;
  providerUserId?: string;
  emailVerified?: boolean;
  avatarUrl?: string;
  sessionContext?: SessionContext;
}): Promise<string> {
  const user =
    params.provider && params.providerUserId
      ? await findOrCreateSocialUser({
          provider: params.provider,
          providerUserId: params.providerUserId,
          email: params.email,
          emailVerified: params.emailVerified ?? false,
          name: params.name,
          avatarUrl: params.avatarUrl,
        })
      : await (async () => {
          let existing = await User.findOne({ email: params.email });
          if (existing) return existing;
          const randomPassword = crypto.randomBytes(32).toString('hex');
          return User.create({
            email: params.email,
            name: params.name,
            password: randomPassword,
          });
        })();

  const { token, refreshToken, sessionId } = await issueTokensForUser(
    user,
    params.sessionContext,
  );
  return createOAuthCode({
    userId: String(user._id),
    token,
    refreshToken,
    sessionId,
    email: user.email,
    name: user.name ?? '',
  });
}

export async function exchangeOAuthCode(req: Request, res: Response): Promise<void> {
  const { code } = req.body as { code?: string };
  if (!code || typeof code !== 'string') {
    res.status(400).json({ message: 'Поле code обязательно' });
    return;
  }

  const record = await OAuthCode.findOneAndDelete({ code });
  if (!record) {
    res.status(404).json({ message: 'Код не найден или уже использован' });
    return;
  }
  if (record.expiresAt.getTime() < Date.now()) {
    res.status(410).json({ message: 'Срок действия кода истёк' });
    return;
  }

  const user = await User.findById(record.userId).select(
    '_id email name authProvider avatarUrl',
  );

  res.json({
    token: record.token,
    refreshToken: record.refreshToken,
    sessionId: record.sessionId,
    user: user
      ? {
          id: user._id,
          email: user.email,
          name: user.name,
          provider: user.authProvider ?? null,
          avatarUrl: user.avatarUrl ?? null,
        }
      : {
          id: String(record.userId),
          email: record.email,
          name: record.name,
        },
  });
}

function exchangeGoogleCode(
  code: string,
  redirectUri: string,
): Promise<{ idToken: string }> {
  return new Promise((resolve, reject) => {
    if (!env.googleClientId || !env.googleClientSecret) {
      reject(
        new Error(
          'Google OAuth не настроен. Задайте GOOGLE_CLIENT_ID и GOOGLE_CLIENT_SECRET в .env',
        ),
      );
      return;
    }

    const body = new URLSearchParams({
      code,
      client_id: env.googleClientId,
      client_secret: env.googleClientSecret,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    }).toString();

    const request = https.request(
      {
        hostname: 'oauth2.googleapis.com',
        path: '/token',
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (googleRes) => {
        let raw = '';
        googleRes.on('data', (chunk) => (raw += chunk));
        googleRes.on('end', () => {
          try {
            const data = JSON.parse(raw) as {
              id_token?: string;
              error?: string;
              error_description?: string;
            };
            if (!data.id_token) {
              reject(
                new Error(data.error_description ?? data.error ?? 'Google не вернул id_token'),
              );
              return;
            }
            resolve({ idToken: data.id_token });
          } catch {
            reject(new Error('Ошибка разбора ответа Google'));
          }
        });
      },
    );

    request.on('error', reject);
    request.write(body);
    request.end();
  });
}

function verifyGoogleToken(
  idToken: string,
): Promise<{
  sub: string;
  email: string;
  name: string;
  emailVerified: boolean;
  picture?: string;
}> {
  return new Promise((resolve, reject) => {
    const url = `https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=${encodeURIComponent(idToken)}`;
    https
      .get(url, (googleRes) => {
        let raw = '';
        googleRes.on('data', (chunk) => (raw += chunk));
        googleRes.on('end', () => {
          try {
            const payload = JSON.parse(raw) as Record<string, string>;
            if (payload.error_description || !payload.email) {
              reject(new Error(payload.error_description ?? 'Invalid Google token'));
              return;
            }
            if (!payload.sub) {
              reject(new Error('Google token не содержит sub'));
              return;
            }
            resolve({
              sub: payload.sub,
              email: payload.email,
              name: payload.name ?? payload.email.split('@')[0],
              emailVerified:
                payload.email_verified === 'true' || payload.email_verified === '1',
              picture: payload.picture,
            });
          } catch {
            reject(new Error('Failed to parse Google tokeninfo response'));
          }
        });
      })
      .on('error', reject);
  });
}

export async function googleCallback(req: Request, res: Response): Promise<void> {
  const { code, error } = req.query as Record<string, string | undefined>;

  if (error) {
    logger.warn(`[googleCallback] OAuth error: ${error}`);
    res.redirect(302, buildOAuthErrorDeepLink(error));
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
    if (!googlePayload.emailVerified) {
      throw new Error('Google account email is not verified');
    }

    const oneTimeCode = await loginOrCreateUserAndIssueCode({
      email: googlePayload.email.toLowerCase().trim(),
      name: googlePayload.name,
      provider: 'google',
      providerUserId: googlePayload.sub,
      emailVerified: true,
      avatarUrl: googlePayload.picture,
      sessionContext: getRequestSessionContext(req),
    });

    logger.info(`[googleCallback] Success: email=${googlePayload.email}`);
    res.redirect(302, buildOAuthCodeDeepLink(oneTimeCode));
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Ошибка авторизации Google';
    logger.error('[googleCallback] Error:', { err });
    res.redirect(302, buildOAuthErrorDeepLink(message));
  }
}

interface AppleJwk {
  kty: string;
  kid: string;
  use: string;
  alg: string;
  n: string;
  e: string;
}

let appleKeysCache: { keys: AppleJwk[]; fetchedAt: number } | null = null;
const APPLE_KEYS_TTL_MS = 60 * 60 * 1000;

function fetchAppleKeys(): Promise<AppleJwk[]> {
  return new Promise((resolve, reject) => {
    https
      .get('https://appleid.apple.com/auth/keys', (appleRes) => {
        let raw = '';
        appleRes.on('data', (chunk) => (raw += chunk));
        appleRes.on('end', () => {
          try {
            const data = JSON.parse(raw) as { keys: AppleJwk[] };
            if (!Array.isArray(data.keys)) {
              reject(new Error('Apple returned invalid JWKS payload'));
              return;
            }
            resolve(data.keys);
          } catch {
            reject(new Error('Failed to parse Apple JWKS response'));
          }
        });
      })
      .on('error', reject);
  });
}

async function getAppleKey(kid: string): Promise<AppleJwk> {
  const now = Date.now();
  if (!appleKeysCache || now - appleKeysCache.fetchedAt > APPLE_KEYS_TTL_MS) {
    appleKeysCache = { keys: await fetchAppleKeys(), fetchedAt: now };
  }

  let key = appleKeysCache.keys.find((item) => item.kid === kid);
  if (!key) {
    appleKeysCache = { keys: await fetchAppleKeys(), fetchedAt: now };
    key = appleKeysCache.keys.find((item) => item.kid === kid);
  }

  if (!key) {
    throw new Error(`Apple public key with kid=${kid} not found`);
  }
  return key;
}

function verifyAppleToken(
  identityToken: string,
): Promise<{ sub: string; email?: string; emailVerified: boolean }> {
  return new Promise((resolve, reject) => {
    (async () => {
      try {
        const decodedHeader = jwt.decode(identityToken, { complete: true });
        if (
          !decodedHeader ||
          typeof decodedHeader === 'string' ||
          !decodedHeader.header.kid
        ) {
          reject(new Error('Некорректный Apple identity token'));
          return;
        }

        const jwk = await getAppleKey(decodedHeader.header.kid);
        const publicKey = crypto.createPublicKey({
          key: jwk as unknown as crypto.JsonWebKey,
          format: 'jwk',
        });
        const pem = publicKey.export({ type: 'spki', format: 'pem' }) as string;

        const payload = jwt.verify(identityToken, pem, {
          algorithms: ['RS256'],
          issuer: 'https://appleid.apple.com',
          audience: env.appleBundleId,
        }) as jwt.JwtPayload;

        if (!payload.sub) {
          reject(new Error('Apple token не содержит sub'));
          return;
        }

        const emailVerifiedRaw = payload['email_verified'];
        resolve({
          sub: payload.sub,
          email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
          emailVerified: emailVerifiedRaw === true || emailVerifiedRaw === 'true',
        });
      } catch (err) {
        reject(err instanceof Error ? err : new Error(String(err)));
      }
    })();
  });
}

function verifyVkToken(accessToken: string): Promise<{ vkId: string; name: string }> {
  return new Promise((resolve, reject) => {
    const url = `https://api.vk.com/method/users.get?access_token=${encodeURIComponent(accessToken)}&v=5.131`;
    https
      .get(url, (vkRes) => {
        let raw = '';
        vkRes.on('data', (chunk) => (raw += chunk));
        vkRes.on('end', () => {
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

export async function socialLogin(req: Request, res: Response): Promise<void> {
  const {
    provider,
    token,
    name: bodyName,
    id: tgId,
    hash: tgHash,
    auth_date: tgAuthDate,
    first_name: tgFirstName,
    last_name: tgLastName,
    username: tgUsername,
    photo_url: tgPhotoUrl,
  } = req.body as {
    provider?: string;
    token?: string;
    name?: string;
    id?: string | number;
    hash?: string;
    auth_date?: string | number;
    first_name?: string;
    last_name?: string;
    username?: string;
    photo_url?: string;
  };

  if (!provider) {
    res.status(400).json({ message: 'Поле provider обязательно' });
    return;
  }

  const allowedProviders: SocialProvider[] = [
    'google',
    'vk',
    'telegram',
    'instagram',
    'apple',
  ];
  if (!allowedProviders.includes(provider as SocialProvider)) {
    res.status(400).json({ message: `Неизвестный провайдер: ${provider}` });
    return;
  }

  if (provider !== 'telegram' && !token) {
    res.status(400).json({ message: 'Поле token обязательно' });
    return;
  }

  let identity: SocialIdentity;

  try {
    if (provider === 'google') {
      const googlePayload = await verifyGoogleToken(token!);
      if (!googlePayload.emailVerified) {
        throw new Error('Google account email is not verified');
      }
      identity = {
        provider: 'google',
        providerUserId: googlePayload.sub,
        email: googlePayload.email.toLowerCase().trim(),
        emailVerified: true,
        name: bodyName ?? googlePayload.name,
        avatarUrl: googlePayload.picture,
      };
    } else if (provider === 'apple') {
      const applePayload = await verifyAppleToken(token!);
      const verifiedEmail =
        applePayload.email && applePayload.emailVerified
          ? applePayload.email.toLowerCase().trim()
          : `apple_${applePayload.sub}@apple.placeholder`;
      identity = {
        provider: 'apple',
        providerUserId: applePayload.sub,
        email: verifiedEmail,
        emailVerified: Boolean(applePayload.email && applePayload.emailVerified),
        name: bodyName ?? verifiedEmail.split('@')[0],
      };
    } else if (provider === 'vk') {
      const vkPayload = await verifyVkToken(token!);
      identity = {
        provider: 'vk',
        providerUserId: vkPayload.vkId,
        email: `vk_${vkPayload.vkId}@vk.placeholder`,
        emailVerified: false,
        name: bodyName ?? vkPayload.name,
      };
    } else if (provider === 'telegram') {
      if (!tgId || !tgHash || !tgAuthDate) {
        res.status(400).json({ message: 'Для Telegram необходимы поля id, hash, auth_date' });
        return;
      }
      if (!env.telegramBotToken) {
        res.status(503).json({ message: 'Telegram login не настроен' });
        return;
      }

      const tgData: TelegramAuthData = {
        id: tgId,
        hash: tgHash,
        auth_date: tgAuthDate,
        ...(tgFirstName && { first_name: tgFirstName }),
        ...(tgLastName && { last_name: tgLastName }),
        ...(tgUsername && { username: tgUsername }),
        ...(tgPhotoUrl && { photo_url: tgPhotoUrl }),
      };

      if (!verifyTelegramAuthData(tgData, env.telegramBotToken)) {
        res.status(401).json({ message: 'Недействительная или устаревшая подпись Telegram' });
        return;
      }

      const fullName = [tgFirstName, tgLastName].filter(Boolean).join(' ');
      identity = {
        provider: 'telegram',
        providerUserId: String(tgId),
        email: `tg_${tgId}@telegram.placeholder`,
        emailVerified: false,
        name: bodyName ?? (fullName || (tgUsername ?? String(tgId))),
        avatarUrl: tgPhotoUrl,
      };
    } else {
      const igProfile = await exchangeInstagramCode(token!, buildInstagramRedirectUri());
      identity = {
        provider: 'instagram',
        providerUserId: igProfile.userId,
        email: `ig_${igProfile.userId}@instagram.placeholder`,
        emailVerified: false,
        name: bodyName ?? igProfile.username,
      };
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Ошибка верификации токена';
    res.status(401).json({ message });
    return;
  }

  try {
    const user = await findOrCreateSocialUser(identity);
    const { token: accessToken, refreshToken, sessionId } = await issueTokensForUser(
      user,
      getRequestSessionContext(req),
    );
    res.json({
      token: accessToken,
      refreshToken,
      sessionId,
      user: {
        id: user._id,
        email: user.email,
        name: user.name,
        provider: user.authProvider ?? null,
        avatarUrl: user.avatarUrl ?? null,
      },
    });
  } catch (err) {
    logger.error('[socialLogin] DB error:', { err });
    res.status(500).json({ message: 'Внутренняя ошибка сервера' });
  }
}

export async function linkTelegramEndpoint(req: AuthRequest, res: Response): Promise<void> {
  const { id, hash, auth_date, first_name, last_name, username, photo_url } =
    req.body as Record<string, string | undefined>;

  if (!id || !hash || !auth_date) {
    res.status(400).json({ message: 'Поля id, hash, auth_date обязательны' });
    return;
  }
  if (!env.telegramBotToken) {
    res.status(503).json({ message: 'Telegram login не настроен' });
    return;
  }

  const tgData: TelegramAuthData = {
    id,
    hash,
    auth_date,
    ...(first_name && { first_name }),
    ...(last_name && { last_name }),
    ...(username && { username }),
    ...(photo_url && { photo_url }),
  };

  if (!verifyTelegramAuthData(tgData, env.telegramBotToken)) {
    res.status(401).json({ message: 'Недействительная или устаревшая подпись Telegram' });
    return;
  }

  const telegramId = String(id);

  const conflict = await User.findOne({ telegramId, _id: { $ne: req.userId } });
  if (conflict) {
    // Если конфликтующий аккаунт — заглушка Telegram (создана при первом входе через TG),
    // переносим telegramId на текущего пользователя и очищаем у заглушки.
    const isPlaceholder = conflict.email.endsWith('@telegram.placeholder');
    if (!isPlaceholder) {
      res.status(409).json({ message: 'Этот Telegram аккаунт уже привязан к другому пользователю' });
      return;
    }
    await User.updateOne({ _id: conflict._id }, { $unset: { telegramId: '' } });
  }

  const user = await User.findById(req.userId);
  if (!user) {
    res.status(404).json({ message: 'Пользователь не найден' });
    return;
  }

  user.telegramId = telegramId;

  if (photo_url && !user.avatarUrl?.startsWith('/')) {
    const localAvatar = await resolveAvatarUrl(photo_url, telegramId);
    if (localAvatar) user.avatarUrl = localAvatar;
  }

  await user.save();
  logger.info(`[linkTelegramEndpoint] Linked telegramId=${telegramId} to userId=${req.userId}`);

  res.json({
    id: user._id,
    email: user.email,
    name: user.name,
    provider: user.authProvider ?? null,
    avatarUrl: user.avatarUrl ?? null,
    hasGoogleLinked: !!user.googleSub,
    hasTelegramLinked: !!user.telegramId,
  });
}
