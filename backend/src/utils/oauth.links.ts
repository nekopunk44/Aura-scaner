export const APP_CALLBACK_SCHEME = 'aurascanner';
export const ANDROID_APP_PACKAGE = 'com.aurascanner.app';

export function buildOAuthCodeDeepLink(code: string): string {
  return `${APP_CALLBACK_SCHEME}://oauth2redirect?code=${encodeURIComponent(code)}`;
}

export function buildOAuthErrorDeepLink(message: string): string {
  return `${APP_CALLBACK_SCHEME}://oauth2redirect?error=${encodeURIComponent(message)}`;
}

export function buildAndroidIntentUri(code: string): string {
  return `intent://oauth2redirect?code=${encodeURIComponent(code)}#Intent;scheme=${APP_CALLBACK_SCHEME};package=${ANDROID_APP_PACKAGE};end`;
}

export function buildInstagramRedirectUri(): string {
  return `${APP_CALLBACK_SCHEME}://oauth2redirect`;
}
