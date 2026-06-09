import https from 'https';
import crypto from 'crypto';
import { env } from '../config/env';
import { logger } from './logger';

// ──────────────────────────────────────────────────────────────────────────────
// Apple App Store: verifyReceipt (Production / Sandbox)
// Docs: https://developer.apple.com/documentation/appstorereceipts/verifyreceipt
// ──────────────────────────────────────────────────────────────────────────────
interface AppleInApp {
  product_id: string;
  transaction_id: string;
  original_transaction_id: string;
  expires_date_ms?: string;
  purchase_date_ms?: string;
}

interface AppleVerifyResponse {
  status: number;
  receipt?: { bundle_id: string; in_app: AppleInApp[] };
  latest_receipt_info?: AppleInApp[];
  pending_renewal_info?: Array<{ auto_renew_status?: string }>;
  environment?: string;
}

export interface VerifiedReceipt {
  productId: string;
  transactionId: string;
  originalTransactionId: string;
  expiresAtMs: number | null;
  isActive: boolean;
}

function appleVerify(
  receiptData: string,
  useSandbox: boolean,
): Promise<AppleVerifyResponse> {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      'receipt-data': receiptData,
      password: env.appleSharedSecret || undefined,
      'exclude-old-transactions': true,
    });

    const options = {
      hostname: useSandbox
        ? 'sandbox.itunes.apple.com'
        : 'buy.itunes.apple.com',
      path: '/verifyReceipt',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let raw = '';
      res.on('data', (chunk) => (raw += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(raw) as AppleVerifyResponse);
        } catch {
          reject(new Error('Не удалось разобрать ответ Apple'));
        }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

export async function verifyAppleReceipt(
  receiptData: string,
  expectedProductId?: string,
): Promise<VerifiedReceipt> {
  // Apple рекомендует сначала production, а потом sandbox при статусе 21007
  let response = await appleVerify(receiptData, env.appleUseSandbox);

  if (response.status === 21007 && !env.appleUseSandbox) {
    // Receipt от sandbox прислан на production — перепроверяем в sandbox
    response = await appleVerify(receiptData, true);
  } else if (response.status === 21008 && env.appleUseSandbox) {
    response = await appleVerify(receiptData, false);
  }

  if (response.status !== 0) {
    throw new Error(`Apple verifyReceipt вернул ошибку ${response.status}`);
  }

  // Проверяем bundle_id
  if (response.receipt?.bundle_id && response.receipt.bundle_id !== env.appleBundleId) {
    throw new Error(
      `Bundle ID не совпадает: ${response.receipt.bundle_id} != ${env.appleBundleId}`,
    );
  }

  // Для подписок берём latest_receipt_info, для не-подписок — receipt.in_app
  const purchases =
    response.latest_receipt_info ?? response.receipt?.in_app ?? [];
  if (purchases.length === 0) {
    throw new Error('Apple receipt не содержит покупок');
  }

  // Берём самую свежую покупку нужного productId
  const filtered = expectedProductId
    ? purchases.filter((p) => p.product_id === expectedProductId)
    : purchases;
  if (filtered.length === 0) {
    throw new Error(`Продукт ${expectedProductId} не найден в receipt`);
  }

  const sorted = filtered.sort((a, b) => {
    const aMs = parseInt(a.purchase_date_ms ?? '0', 10);
    const bMs = parseInt(b.purchase_date_ms ?? '0', 10);
    return bMs - aMs;
  });
  const latest = sorted[0];

  const expiresAtMs = latest.expires_date_ms
    ? parseInt(latest.expires_date_ms, 10)
    : null;
  const isActive = expiresAtMs === null || expiresAtMs > Date.now();

  return {
    productId: latest.product_id,
    transactionId: latest.transaction_id,
    originalTransactionId: latest.original_transaction_id,
    expiresAtMs,
    isActive,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Google Play Developer API: subscriptions.get
// Docs: https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptions/get
// ──────────────────────────────────────────────────────────────────────────────
interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface GoogleSubscriptionResponse {
  expiryTimeMillis?: string;
  startTimeMillis?: string;
  paymentState?: number;
  cancelReason?: number;
  orderId?: string;
  autoRenewing?: boolean;
}

let _googleTokenCache: { token: string; expiresAt: number } | null = null;

function loadServiceAccount(): ServiceAccount {
  if (!env.googlePlayServiceAccountJson) {
    throw new Error(
      'GOOGLE_PLAY_SERVICE_ACCOUNT_JSON не настроен в .env',
    );
  }
  try {
    return JSON.parse(env.googlePlayServiceAccountJson) as ServiceAccount;
  } catch {
    throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON содержит невалидный JSON');
  }
}

function base64UrlEncode(buf: Buffer | string): string {
  const b = typeof buf === 'string' ? Buffer.from(buf) : buf;
  return b
    .toString('base64')
    .replace(/=+$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

async function getGoogleAccessToken(): Promise<string> {
  const now = Date.now();
  if (_googleTokenCache && _googleTokenCache.expiresAt > now + 60 * 1000) {
    return _googleTokenCache.token;
  }

  const sa = loadServiceAccount();
  const iat = Math.floor(now / 1000);
  const exp = iat + 3600;

  const header = base64UrlEncode(
    JSON.stringify({ alg: 'RS256', typ: 'JWT' }),
  );
  const payload = base64UrlEncode(
    JSON.stringify({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: sa.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat,
      exp,
    }),
  );
  const signingInput = `${header}.${payload}`;
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(signingInput)
    .sign(sa.private_key);
  const assertion = `${signingInput}.${base64UrlEncode(signature)}`;

  const tokenResponse = await new Promise<{
    access_token?: string;
    expires_in?: number;
    error?: string;
  }>((resolve, reject) => {
    const body = new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString();
    const req = https.request(
      {
        hostname: 'oauth2.googleapis.com',
        path: '/token',
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => (raw += chunk));
        res.on('end', () => {
          try {
            resolve(JSON.parse(raw));
          } catch {
            reject(new Error('Не удалось разобрать ответ Google OAuth'));
          }
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });

  if (!tokenResponse.access_token) {
    throw new Error(
      `Google не вернул access_token: ${tokenResponse.error ?? 'unknown'}`,
    );
  }

  _googleTokenCache = {
    token: tokenResponse.access_token,
    expiresAt: now + (tokenResponse.expires_in ?? 3600) * 1000,
  };
  return _googleTokenCache.token;
}

export async function verifyGooglePlaySubscription(
  productId: string,
  purchaseToken: string,
): Promise<VerifiedReceipt> {
  if (!env.googlePlayPackageName) {
    throw new Error('GOOGLE_PLAY_PACKAGE_NAME не настроен в .env');
  }
  const accessToken = await getGoogleAccessToken();
  const url = `/androidpublisher/v3/applications/${encodeURIComponent(
    env.googlePlayPackageName,
  )}/purchases/subscriptions/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(
    purchaseToken,
  )}`;

  const response = await new Promise<GoogleSubscriptionResponse & { error?: { message: string } }>(
    (resolve, reject) => {
      const req = https.request(
        {
          hostname: 'androidpublisher.googleapis.com',
          path: url,
          method: 'GET',
          headers: { Authorization: `Bearer ${accessToken}` },
        },
        (res) => {
          let raw = '';
          res.on('data', (chunk) => (raw += chunk));
          res.on('end', () => {
            try {
              resolve(JSON.parse(raw));
            } catch {
              reject(new Error('Не удалось разобрать ответ Google Play'));
            }
          });
        },
      );
      req.on('error', reject);
      req.end();
    },
  );

  if (response.error) {
    throw new Error(`Google Play вернул ошибку: ${response.error.message}`);
  }

  const expiresAtMs = response.expiryTimeMillis
    ? parseInt(response.expiryTimeMillis, 10)
    : null;
  // paymentState: 0 = pending, 1 = received, 2 = free trial, 3 = pending deferred upgrade
  const paid = response.paymentState === 1 || response.paymentState === 2;
  const isActive = paid && (expiresAtMs === null || expiresAtMs > Date.now());

  return {
    productId,
    transactionId: response.orderId ?? purchaseToken,
    originalTransactionId: response.orderId ?? purchaseToken,
    expiresAtMs,
    isActive,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Универсальная точка входа
// ──────────────────────────────────────────────────────────────────────────────
export async function verifyReceipt(
  platform: 'ios' | 'android',
  productId: string,
  receiptData: string,
): Promise<VerifiedReceipt> {
  try {
    if (platform === 'ios') {
      return await verifyAppleReceipt(receiptData, productId);
    }
    return await verifyGooglePlaySubscription(productId, receiptData);
  } catch (err) {
    logger.warn('[verifyReceipt] failed', { platform, productId, err });
    throw err;
  }
}
