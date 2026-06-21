import { NextFunction, Request, Response, Router } from 'express';
import multer from 'multer';
import {
  analyzeDocument,
  dewatermarkImage,
  recognizeOcrText,
  removeWatermarks,
  restorePhoto,
  transcribeVoiceNote,
} from '../controllers/ai.controller';
import { authMiddleware } from '../middleware/auth.middleware';
import { audioUpload } from '../middleware/upload.middleware';

const router = Router();

router.post('/analyze', authMiddleware, analyzeDocument);
router.post('/ocr', authMiddleware, recognizeOcrText);
router.post('/restore', authMiddleware, restorePhoto);
router.post('/remove-watermarks', authMiddleware, removeWatermarks);
router.post('/dewatermark', authMiddleware, dewatermarkImage);
router.post(
  '/transcribe',
  authMiddleware,
  (req: Request, res: Response, next: NextFunction) => {
    audioUpload.single('audio')(req, res, (err) => {
      if (err instanceof multer.MulterError) {
        res.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({
          message:
            err.code === 'LIMIT_FILE_SIZE'
              ? 'Audio file is too large'
              : `Audio upload failed: ${err.message}`,
        });
        return;
      }
      if (err) {
        res.status(400).json({
          message: err.message ?? 'Unsupported audio format',
        });
        return;
      }
      next();
    });
  },
  transcribeVoiceNote,
);

export default router;
