const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const { verifyTelegramAuthData } = require('../dist/utils/telegramAuth.js');

function signTelegramPayload(payload, botToken) {
  const checkString = Object.entries(payload)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');

  const secretKey = crypto.createHash('sha256').update(botToken).digest();
  return crypto.createHmac('sha256', secretKey).update(checkString).digest('hex');
}

test('telegram auth rejects empty bot token', () => {
  const authDate = Math.floor(Date.now() / 1000);
  const payload = {
    id: '42',
    auth_date: authDate,
    first_name: 'Aura',
  };
  const hash = signTelegramPayload(payload, '123456:bot-token');

  assert.equal(
    verifyTelegramAuthData({ ...payload, hash }, ''),
    false,
  );
});

test('telegram auth accepts valid recent payload', () => {
  const botToken = '123456:bot-token';
  const payload = {
    id: '42',
    auth_date: Math.floor(Date.now() / 1000),
    first_name: 'Aura',
    username: 'scanner',
  };
  const hash = signTelegramPayload(payload, botToken);

  assert.equal(
    verifyTelegramAuthData({ ...payload, hash }, botToken),
    true,
  );
});

test('telegram auth rejects stale payload', () => {
  const botToken = '123456:bot-token';
  const payload = {
    id: '42',
    auth_date: Math.floor(Date.now() / 1000) - 7200,
  };
  const hash = signTelegramPayload(payload, botToken);

  assert.equal(
    verifyTelegramAuthData({ ...payload, hash }, botToken),
    false,
  );
});
