import mongoose, { Schema } from 'mongoose';

const revokedTokenSchema = new Schema({
  token: { type: String, required: true, unique: true },
  expiresAt: { type: Date, required: true },
});
// TTL-индекс: MongoDB сам удалит запись когда истечёт JWT
revokedTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const RevokedToken = mongoose.model('RevokedToken', revokedTokenSchema);
