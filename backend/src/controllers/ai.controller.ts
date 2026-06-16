import { Response } from 'express';
import https from 'https';
import { env } from '../config/env';
import { AuthRequest } from '../middleware/auth.middleware';
import { logger } from '../utils/logger';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
// Список моделей-кандидатов (env OPENROUTER_MODEL, через запятую). Должны
// быть vision-моделями — запросы содержат image_url.
const AI_MODELS = env.openRouterModel
  .split(',')
  .map((m) => m.trim())
  .filter(Boolean);

interface OpenRouterResult {
  ok: boolean;
  status: number;
  text?: string;   // успешный ответ модели
  detail?: string; // сообщение об ошибке от OpenRouter
}

/// Один запрос к OpenRouter с конкретной моделью.
function callOpenRouter(model: string, messages: unknown): Promise<OpenRouterResult> {
  return new Promise((resolve) => {
    const payload = JSON.stringify({ model, messages });
    const url = new URL(OPENROUTER_URL);
    const proxyReq = https.request(
      {
        method: 'POST',
        hostname: url.hostname,
        path: url.pathname,
        port: 443,
        headers: {
          Authorization: `Bearer ${env.openRouterApiKey}`,
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://aura-scanner.app',
          'X-Title': 'Aura Scanner',
          'Content-Length': Buffer.byteLength(payload),
        },
      },
      (proxyRes) => {
        let data = '';
        proxyRes.on('data', (chunk) => { data += chunk; });
        proxyRes.on('end', () => {
          const status = proxyRes.statusCode ?? 0;
          if (status !== 200) {
            let detail = '';
            try { detail = JSON.parse(data)?.error?.message ?? ''; } catch { /* not json */ }
            resolve({ ok: false, status, detail });
            return;
          }
          try {
            const text = JSON.parse(data)?.choices?.[0]?.message?.content;
            if (typeof text !== 'string') throw new Error('unexpected shape');
            resolve({ ok: true, status, text });
          } catch {
            resolve({ ok: false, status, detail: 'Некорректный ответ от AI сервиса' });
          }
        });
      },
    );
    proxyReq.on('error', (err) => {
      logger.error('[analyzeDocument] request error', { err, model });
      resolve({ ok: false, status: 0, detail: 'Не удалось связаться с AI сервисом' });
    });
    proxyReq.write(payload);
    proxyReq.end();
  });
}

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

  // Фолбэк-цепочка: пробуем модели по очереди, берём первую успешную.
  // Так бесшовно переживаем перевод free-моделей в платные / залоченные.
  let lastDetail = '';
  for (const model of AI_MODELS) {
    const result = await callOpenRouter(model, messages);
    if (result.ok && result.text) {
      res.json({ result: result.text });
      return;
    }
    lastDetail = result.detail ?? '';
    logger.warn('[analyzeDocument] model failed, trying next', {
      model, status: result.status, detail: lastDetail,
    });
  }

  res.status(502).json({ message: 'Ошибка AI сервиса', detail: lastDetail });
}
