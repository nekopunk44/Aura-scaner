import { Response } from 'express';
import path from 'path';
import fs from 'fs';
import mongoose from 'mongoose';
import { DocumentModel, DocumentFormat } from '../models/Document';
import { AuthRequest } from '../middleware/auth.middleware';
import { env } from '../config/env';
import { logger } from '../utils/logger';

const MIME_TO_FORMAT: Record<string, DocumentFormat> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'text/plain': 'txt',
};

function isValidObjectId(id: string): boolean {
  return mongoose.Types.ObjectId.isValid(id);
}

export async function uploadDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!req.file) {
    res.status(400).json({ message: 'Файл не загружен' });
    return;
  }

  const format = MIME_TO_FORMAT[req.file.mimetype];
  if (!format) {
    fs.unlink(path.resolve(env.uploadDir, req.file.filename), () => {});
    res.status(400).json({ message: 'Неподдерживаемый тип файла' });
    return;
  }

  const rawName = (req.body.name as string | undefined) || path.parse(req.file.originalname).name;
  const name = rawName.trim().slice(0, 255) || 'Документ';

  try {
    const doc = await DocumentModel.create({
      userId: req.userId,
      name,
      format,
      filePath: req.file.filename,
      fileSize: req.file.size,
      mimeType: req.file.mimetype,
    });
    res.status(201).json(doc);
  } catch (err) {
    // Если БД упала после сохранения файла — удаляем файл чтобы не было мусора
    const diskPath = path.resolve(env.uploadDir, req.file.filename);
    if (fs.existsSync(diskPath)) fs.unlinkSync(diskPath);
    logger.error('[uploadDocument]', err);
    res.status(500).json({ message: 'Ошибка при сохранении документа' });
  }
}

export async function listDocuments(req: AuthRequest, res: Response): Promise<void> {
  try {
    // Пагинация: limit ограничен сверху чтобы юзер не мог запросить миллион
    // записей одним запросом. Клиент, отправивший старый формат без query —
    // получит первые 100 документов и пагинационный заголовок Х-Total-Count.
    const rawLimit = parseInt(req.query['limit'] as string ?? '100', 10);
    const rawOffset = parseInt(req.query['offset'] as string ?? '0', 10);
    const limit = Math.min(Math.max(Number.isFinite(rawLimit) ? rawLimit : 100, 1), 200);
    const offset = Math.max(Number.isFinite(rawOffset) ? rawOffset : 0, 0);

    const [docs, total] = await Promise.all([
      DocumentModel.find({ userId: req.userId })
        .sort({ createdAt: -1 })
        .skip(offset)
        .limit(limit),
      DocumentModel.countDocuments({ userId: req.userId }),
    ]);

    res.setHeader('X-Total-Count', String(total));
    res.json({ items: docs, total, limit, offset });
  } catch (err) {
    logger.error('[listDocuments]', err);
    res.status(500).json({ message: 'Ошибка при получении документов' });
  }
}

export async function downloadDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!isValidObjectId(req.params.id)) {
    res.status(400).json({ message: 'Некорректный идентификатор документа' });
    return;
  }

  try {
    const doc = await DocumentModel.findOne({ _id: req.params.id, userId: req.userId });
    if (!doc) {
      res.status(404).json({ message: 'Документ не найден' });
      return;
    }

    const filePath = path.resolve(env.uploadDir, doc.filePath);
    if (!fs.existsSync(filePath)) {
      res.status(404).json({ message: 'Файл не найден на диске' });
      return;
    }

    res.download(filePath, `${doc.name}.${doc.format}`);
  } catch (err) {
    logger.error('[downloadDocument]', err);
    res.status(500).json({ message: 'Ошибка при скачивании документа' });
  }
}

export async function thumbnailDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!isValidObjectId(req.params.id)) {
    res.status(400).json({ message: 'Некорректный идентификатор' });
    return;
  }
  try {
    const doc = await DocumentModel.findOne({ _id: req.params.id, userId: req.userId });
    if (!doc || !['jpg', 'jpeg', 'png'].includes(doc.format)) {
      res.status(404).json({ message: 'Превью недоступно' });
      return;
    }
    const filePath = path.resolve(env.uploadDir, doc.filePath);
    if (!fs.existsSync(filePath)) {
      res.status(404).json({ message: 'Файл не найден' });
      return;
    }
    res.setHeader('Content-Type', doc.mimeType);
    res.setHeader('Cache-Control', 'private, max-age=3600');
    res.sendFile(filePath);
  } catch (err) {
    logger.error('[thumbnailDocument]', err);
    res.status(500).json({ message: 'Ошибка при получении превью' });
  }
}

export async function renameDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!isValidObjectId(req.params.id)) {
    res.status(400).json({ message: 'Некорректный идентификатор документа' });
    return;
  }

  const { name } = req.body;
  if (!name || typeof name !== 'string' || !name.trim()) {
    res.status(400).json({ message: 'Новое имя обязательно' });
    return;
  }

  try {
    const doc = await DocumentModel.findOneAndUpdate(
      { _id: req.params.id, userId: req.userId },
      { name: name.trim().slice(0, 255) },
      { new: true }
    );

    if (!doc) {
      res.status(404).json({ message: 'Документ не найден' });
      return;
    }

    res.json(doc);
  } catch (err) {
    logger.error('[renameDocument]', err);
    res.status(500).json({ message: 'Ошибка при переименовании документа' });
  }
}

export async function deleteDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!isValidObjectId(req.params.id)) {
    res.status(400).json({ message: 'Некорректный идентификатор документа' });
    return;
  }

  try {
    const doc = await DocumentModel.findOneAndDelete({ _id: req.params.id, userId: req.userId });
    if (!doc) {
      res.status(404).json({ message: 'Документ не найден' });
      return;
    }

    // Удаляем файл с диска — если его уже нет, просто игнорируем
    const filePath = path.resolve(env.uploadDir, doc.filePath);
    try {
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    } catch (fsErr) {
      logger.warn('[deleteDocument] Не удалось удалить файл с диска:', fsErr);
    }

    res.json({ message: 'Документ удалён' });
  } catch (err) {
    logger.error('[deleteDocument]', err);
    res.status(500).json({ message: 'Ошибка при удалении документа' });
  }
}
