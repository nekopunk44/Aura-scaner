const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildAndroidIntentUri,
  buildInstagramRedirectUri,
  buildOAuthCodeDeepLink,
} = require('../dist/utils/oauth.links.js');

test('android intent uses production package id', () => {
  const uri = buildAndroidIntentUri('abc123');
  assert.match(uri, /package=com\.aurascanner\.app/);
  assert.doesNotMatch(uri, /com\.example\.scanner_ap/);
});

test('oauth deep link keeps aurascanner scheme', () => {
  assert.equal(
    buildOAuthCodeDeepLink('abc123'),
    'aurascanner://oauth2redirect?code=abc123',
  );
});

test('instagram redirect uri uses app callback scheme', () => {
  assert.equal(buildInstagramRedirectUri(), 'aurascanner://oauth2redirect');
});
