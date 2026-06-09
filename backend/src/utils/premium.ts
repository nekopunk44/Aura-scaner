import { User, IUser } from '../models/User';
import { logger } from '../utils/logger';

/**
 * Активна ли подписка у юзера прямо сейчас.
 *
 * Премиум считается активным если:
 *   1) `isPremium: true` в БД и
 *   2) либо нет `premiumExpiresAt` (пожизненная), либо она в будущем.
 *
 * Используется на чтении (профиль, premium-gated фичи), потому что фоновая
 * чистка может отстать от точного момента истечения.
 */
export function isPremiumActive(user: Pick<IUser, 'isPremium' | 'premiumExpiresAt'>): boolean {
  if (!user.isPremium) return false;
  if (!user.premiumExpiresAt) return true;
  return user.premiumExpiresAt.getTime() > Date.now();
}

/**
 * Фоновая чистка: переводит истёкшие премиумы в `isPremium: false` пачкой.
 * Чтобы аналитика/отчёты по подпискам были согласованы с реальностью.
 *
 * Запускается из app.ts один раз при старте и каждый час setInterval'ом.
 */
export async function sweepExpiredPremiums(): Promise<number> {
  try {
    const result = await User.updateMany(
      {
        isPremium: true,
        premiumExpiresAt: { $exists: true, $ne: null, $lte: new Date() },
      },
      { $set: { isPremium: false } },
    );
    const n = result.modifiedCount ?? 0;
    if (n > 0) logger.info(`[sweepExpiredPremiums] Deactivated ${n} expired premiums`);
    return n;
  } catch (err) {
    logger.error('[sweepExpiredPremiums]', { err });
    return 0;
  }
}

const SWEEP_INTERVAL_MS = 60 * 60 * 1000; // 1 час
let _sweepTimer: NodeJS.Timeout | null = null;

export function startPremiumSweeper(): void {
  if (_sweepTimer) return;
  // Первый прогон сразу при старте, затем каждый час
  void sweepExpiredPremiums();
  _sweepTimer = setInterval(() => void sweepExpiredPremiums(), SWEEP_INTERVAL_MS);
  _sweepTimer.unref?.(); // не мешать graceful shutdown
}

export function stopPremiumSweeper(): void {
  if (_sweepTimer) {
    clearInterval(_sweepTimer);
    _sweepTimer = null;
  }
}
