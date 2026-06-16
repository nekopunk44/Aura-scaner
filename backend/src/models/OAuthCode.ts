import mongoose, { Document, Schema } from 'mongoose';

/**
 * Одноразовый код для безопасного обмена OAuth-результатов на JWT.
 *
 * Backend кладёт сюда {token, refreshToken, userId} и редиректит клиент на
 * `aurascanner://oauth2redirect?code=<code>` — БЕЗ самих токенов в URL.
 *
 * Клиент потом обменивает code на токены через POST /api/auth/oauth/exchange.
 * После обмена запись удаляется. TTL — 5 минут.
 */
export interface IOAuthCode extends Document {
  code: string;
  userId: mongoose.Types.ObjectId;
  token: string;
  refreshToken: string;
  sessionId: string;
  email: string;
  name: string;
  expiresAt: Date;
}

const oauthCodeSchema = new Schema<IOAuthCode>({
  code: { type: String, required: true, unique: true, index: true },
  userId: { type: Schema.Types.ObjectId, required: true, ref: 'User' },
  token: { type: String, required: true },
  refreshToken: { type: String, required: true },
  sessionId: { type: String, required: true },
  email: { type: String, required: true },
  name: { type: String, default: '' },
  expiresAt: { type: Date, required: true },
});
oauthCodeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const OAuthCode = mongoose.model<IOAuthCode>('OAuthCode', oauthCodeSchema);
