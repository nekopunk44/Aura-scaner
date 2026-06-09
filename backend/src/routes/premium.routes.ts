import { Router } from 'express';
import { activatePremium, deactivatePremium } from '../controllers/premium.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/activate', authMiddleware, activatePremium);
router.delete('/deactivate', authMiddleware, deactivatePremium);

export default router;
