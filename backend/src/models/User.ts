import mongoose, { Document, Schema } from 'mongoose';
import bcrypt from 'bcryptjs';

export interface IUser extends Document {
  email: string;
  password: string;
  name: string;
  googleSub?: string;
  appleSub?: string;
  vkUserId?: string;
  telegramId?: string;
  instagramUserId?: string;
  isPremium: boolean;
  premiumActivatedAt?: Date;
  premiumExpiresAt?: Date;
  premiumPlatform?: 'ios' | 'android';
  premiumProductId?: string;
  premiumOriginalTransactionId?: string;
  createdAt: Date;
  comparePassword(candidate: string): Promise<boolean>;
}

const userSchema = new Schema<IUser>(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    password: { type: String, required: true, minlength: 6 },
    name: { type: String, required: true, trim: true },
    googleSub: { type: String, unique: true, sparse: true, trim: true },
    appleSub: { type: String, unique: true, sparse: true, trim: true },
    vkUserId: { type: String, unique: true, sparse: true, trim: true },
    telegramId: { type: String, unique: true, sparse: true, trim: true },
    instagramUserId: { type: String, unique: true, sparse: true, trim: true },
    isPremium: { type: Boolean, default: false },
    premiumActivatedAt: { type: Date },
    premiumExpiresAt: { type: Date },
    premiumPlatform: { type: String, enum: ['ios', 'android'] },
    premiumProductId: { type: String },
    premiumOriginalTransactionId: { type: String, index: true },
  },
  { timestamps: true }
);

userSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  this.password = await bcrypt.hash(this.password, 12);
  next();
});

userSchema.methods.comparePassword = function (candidate: string): Promise<boolean> {
  return bcrypt.compare(candidate, this.password);
};

export const User = mongoose.model<IUser>('User', userSchema);
