import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { v4 as uuidv4 } from 'uuid';
import { env } from '../config/env';

const ALLOWED_MIME_TYPES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'text/plain',
];

const ALLOWED_AUDIO_MIME_TYPES = [
  'audio/aac',
  'audio/m4a',
  'audio/mp4',
  'audio/mpeg',
  'audio/ogg',
  'audio/wav',
  'audio/webm',
  'audio/x-m4a',
  'audio/x-wav',
];

const ALLOWED_AUDIO_EXTENSIONS = new Set([
  '.aac',
  '.m4a',
  '.mp3',
  '.mp4',
  '.ogg',
  '.wav',
  '.webm',
]);

function ensureUploadDir(dir: string): void {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    const dir = path.resolve(env.uploadDir);
    ensureUploadDir(dir);
    cb(null, dir);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${uuidv4()}${ext}`);
  },
});

export const upload = multer({
  storage,
  limits: { fileSize: env.maxFileSizeMb * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MIME_TYPES.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`Формат файла не поддерживается: ${file.mimetype}`));
    }
  },
});

export const audioUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: Math.min(env.maxFileSizeMb, 25) * 1024 * 1024,
    files: 1,
  },
  fileFilter: (_req, file, cb) => {
    const extension = path.extname(file.originalname).toLowerCase();
    if (
      ALLOWED_AUDIO_MIME_TYPES.includes(file.mimetype) ||
      ALLOWED_AUDIO_EXTENSIONS.has(extension)
    ) {
      cb(null, true);
    } else {
      cb(new Error(`Unsupported audio format: ${file.mimetype}`));
    }
  },
});
