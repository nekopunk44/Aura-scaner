import { Router } from 'express';
import { analyzeDocument } from '../controllers/ai.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/analyze', authMiddleware, analyzeDocument);

export default router;
