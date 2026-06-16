import mongoose, { Document, Schema } from 'mongoose';

export interface IRefreshToken extends Document {
  userId: mongoose.Types.ObjectId;
  sessionId: string;
  token: string;
  startedAt: Date;
  lastUsedAt: Date;
  userAgent?: string;
  ipAddress?: string;
  expiresAt: Date;
}

const refreshTokenSchema = new Schema<IRefreshToken>({
  userId: { type: Schema.Types.ObjectId, required: true, ref: 'User' },
  sessionId: { type: String, required: true, index: true, trim: true },
  token: { type: String, required: true, unique: true },
  startedAt: { type: Date, required: true },
  lastUsedAt: { type: Date, required: true },
  userAgent: { type: String, trim: true },
  ipAddress: { type: String, trim: true },
  expiresAt: { type: Date, required: true },
});
refreshTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
refreshTokenSchema.index({ userId: 1, sessionId: 1 }, { unique: true });

export const RefreshToken = mongoose.model<IRefreshToken>('RefreshToken', refreshTokenSchema);
