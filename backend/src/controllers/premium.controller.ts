import { Response } from 'express';
import { AuthRequest } from '../middleware/auth.middleware';
import { User } from '../models/User';
import { logger } from '../utils/logger';
import { verifyReceipt } from '../utils/receipt.verifier';

// POST /api/premium/activate
// Body: { platform: 'ios' | 'android', productId: string, receipt: string }
// Сервер проверяет receipt напрямую у Apple/Google и активирует Premium только
// если покупка действительно есть и не истекла.
export async function activatePremium(req: AuthRequest, res: Response): Promise<void> {
  const { platform, productId, receipt } = req.body as {
    platform?: string;
    productId?: string;
    receipt?: string;
  };

  if (platform !== 'ios' && platform !== 'android') {
    res.status(400).json({ message: 'Поле platform должно быть "ios" или "android"' });
    return;
  }
  if (!productId || typeof productId !== 'string') {
    res.status(400).json({ message: 'Поле productId обязательно' });
    return;
  }
  if (!receipt || typeof receipt !== 'string') {
    res.status(400).json({ message: 'Поле receipt обязательно' });
    return;
  }

  try {
    const verified = await verifyReceipt(platform, productId, receipt);

    if (!verified.isActive) {
      res.status(400).json({
        message: 'Подписка не активна или истекла',
        expiresAt: verified.expiresAtMs,
      });
      return;
    }

    // Защита от повторного использования receipt другим аккаунтом
    const existingUserWithTx = await User.findOne({
      premiumOriginalTransactionId: verified.originalTransactionId,
      _id: { $ne: req.userId },
    }).select('_id');

    if (existingUserWithTx) {
      logger.warn(
        `[activatePremium] Receipt reuse attempt: txId=${verified.originalTransactionId} userId=${req.userId} owner=${existingUserWithTx._id}`,
      );
      res.status(409).json({ message: 'Эта покупка привязана к другому аккаунту' });
      return;
    }

    const user = await User.findByIdAndUpdate(
      req.userId,
      {
        isPremium: true,
        premiumActivatedAt: new Date(),
        premiumExpiresAt: verified.expiresAtMs ? new Date(verified.expiresAtMs) : undefined,
        premiumPlatform: platform,
        premiumProductId: verified.productId,
        premiumOriginalTransactionId: verified.originalTransactionId,
      },
      { new: true },
    ).select('_id isPremium premiumActivatedAt premiumExpiresAt');

    if (!user) {
      res.status(404).json({ message: 'Пользователь не найден' });
      return;
    }

    res.json({
      isPremium: true,
      premiumActivatedAt: user.premiumActivatedAt,
      premiumExpiresAt: user.premiumExpiresAt,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Ошибка проверки покупки';
    logger.error('[activatePremium]', { err });
    res.status(400).json({ message });
  }
}

// DELETE /api/premium/deactivate  (admin / refund flow)
export async function deactivatePremium(req: AuthRequest, res: Response): Promise<void> {
  try {
    await User.findByIdAndUpdate(req.userId, {
      isPremium: false,
      premiumExpiresAt: null,
    });
    res.json({ isPremium: false });
  } catch (err) {
    logger.error('[deactivatePremium]', { err });
    res.status(500).json({ message: 'Ошибка при деактивации Premium' });
  }
}
