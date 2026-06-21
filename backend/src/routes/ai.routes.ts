import { Router } from 'express';
import {
  analyzeDocument,
  recognizeOcrText,
  removeWatermarks,
  restorePhoto,
} from '../controllers/ai.controller';
import { authMiddleware } from '../middleware/auth.middleware';

const router = Router();

router.post('/analyze', authMiddleware, analyzeDocument);
router.post('/ocr', authMiddleware, recognizeOcrText);
router.post('/restore', authMiddleware, restorePhoto);
router.post('/remove-watermarks', authMiddleware, removeWatermarks);

export default router;
