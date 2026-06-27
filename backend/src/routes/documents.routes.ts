import { Router, Request, Response, NextFunction } from 'express';
import multer from 'multer';
import { authMiddleware } from '../middleware/auth.middleware';
import { upload } from '../middleware/upload.middleware';
import {
  uploadDocument,
  listDocuments,
  downloadDocument,
  thumbnailDocument,
  renameDocument,
  deleteDocument,
} from '../controllers/documents.controller';

const router = Router();

router.use(authMiddleware);

router.get('/', listDocuments);

// Оборачиваем multer вручную чтобы перехватить его ошибки (размер, тип файла)
router.post('/upload', (req: Request, res: Response, next: NextFunction) => {
  upload.single('file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        res.status(413).json({ message: 'Файл слишком большой' });
      } else {
        res.status(400).json({ message: `Ошибка загрузки: ${err.message}` });
      }
      return;
    }
    if (err) {
      res.status(400).json({ message: err.message ?? 'Формат файла не поддерживается' });
      return;
    }
    next();
  });
}, uploadDocument);

router.get('/:id/download', downloadDocument);
router.get('/:id/thumbnail', thumbnailDocument);
router.patch('/:id', renameDocument);
router.delete('/:id', deleteDocument);

export default router;
