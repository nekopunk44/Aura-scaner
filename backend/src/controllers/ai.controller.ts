import { Response } from 'express';
import https from 'https';
import { env } from '../config/env';
import { AuthRequest } from '../middleware/auth.middleware';
import { logger } from '../utils/logger';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const AI_MODEL = 'google/gemma-4-31b-it:free';

export async function analyzeDocument(req: AuthRequest, res: Response): Promise<void> {
  if (!env.openRouterApiKey) {
    res.status(503).json({ message: 'AI сервис не настроен' });
    return;
  }

  const { messages } = req.body;
  if (!Array.isArray(messages) || messages.length === 0) {
    res.status(400).json({ message: 'Поле messages обязательно' });
    return;
  }

  const payload = JSON.stringify({ model: AI_MODEL, messages });

  const options = {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${env.openRouterApiKey}`,
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://aura-scanner.app',
      'X-Title': 'Aura Scanner',
      'Content-Length': Buffer.byteLength(payload),
    },
  };

  const url = new URL(OPENROUTER_URL);
  const reqOptions = { ...options, hostname: url.hostname, path: url.pathname, port: 443 };

  const proxyReq = https.request(reqOptions, (proxyRes) => {
    let data = '';
    proxyRes.on('data', (chunk) => { data += chunk; });
    proxyRes.on('end', () => {
      if (proxyRes.statusCode !== 200) {
        logger.warn('[analyzeDocument] OpenRouter error', { status: proxyRes.statusCode, body: data });
        res.status(502).json({ message: 'Ошибка AI сервиса' });
        return;
      }
      try {
        const parsed = JSON.parse(data);
        const text = parsed?.choices?.[0]?.message?.content;
        if (typeof text !== 'string') throw new Error('unexpected shape');
        res.json({ result: text });
      } catch {
        res.status(502).json({ message: 'Некорректный ответ от AI сервиса' });
      }
    });
  });

  proxyReq.on('error', (err) => {
    if (!res.headersSent) {
      logger.error('[analyzeDocument] request error', { err });
      res.status(502).json({ message: 'Не удалось связаться с AI сервисом' });
    }
  });

  proxyReq.write(payload);
  proxyReq.end();
}
