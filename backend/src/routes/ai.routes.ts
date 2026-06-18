import { Router } from 'express';
import { analyzeDocument, recognizeOcrText } from '../controllers/ai.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/analyze', authMiddleware, analyzeDocument);
router.post('/ocr', authMiddleware, recognizeOcrText);

export default router;
