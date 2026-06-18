import { Response } from 'express';
import https from 'https';
import { env } from '../config/env';
import { AuthRequest } from '../middleware/auth.middleware';
import { logger } from '../utils/logger';

const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
const AI_MODELS = env.openRouterModel
  .split(',')
  .map((model) => model.trim())
  .filter(Boolean);
const OCR_MODELS = env.openRouterOcrModel
  .split(',')
  .map((model) => model.trim())
  .filter(Boolean);
const MAX_OCR_IMAGE_BASE64_LENGTH = 8_500_000;

interface OpenRouterResult {
  ok: boolean;
  status: number;
  text?: string;
  detail?: string;
}

interface OpenRouterOptions {
  maxTokens?: number;
  temperature?: number;
}

function callOpenRouter(
  model: string,
  messages: unknown,
  options: OpenRouterOptions = {},
): Promise<OpenRouterResult> {
  return new Promise((resolve) => {
    const payload = JSON.stringify({
      model,
      messages,
      ...(options.maxTokens ? { max_tokens: options.maxTokens } : {}),
      ...(typeof options.temperature === 'number'
        ? { temperature: options.temperature }
        : {}),
    });
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
        proxyRes.on('data', (chunk) => {
          data += chunk;
        });
        proxyRes.on('end', () => {
          const status = proxyRes.statusCode ?? 0;
          if (status !== 200) {
            let detail = '';
            try {
              detail = JSON.parse(data)?.error?.message ?? '';
            } catch {
              detail = data.slice(0, 500);
            }
            resolve({ ok: false, status, detail });
            return;
          }
          try {
            const text = JSON.parse(data)?.choices?.[0]?.message?.content;
            if (typeof text !== 'string') throw new Error('unexpected shape');
            resolve({ ok: true, status, text });
          } catch {
            resolve({
              ok: false,
              status,
              detail: 'Unexpected AI service response',
            });
          }
        });
      },
    );
    proxyReq.on('error', (err) => {
      logger.error('[callOpenRouter] request error', { err, model });
      resolve({
        ok: false,
        status: 0,
        detail: 'Unable to connect to AI service',
      });
    });
    proxyReq.write(payload);
    proxyReq.end();
  });
}

function normalizeImagePayload(
  imageBase64: string,
  mimeType?: string,
): { dataUrl: string; base64Length: number } | null {
  const trimmed = imageBase64.trim();
  const dataUrlMatch = trimmed.match(
    /^data:(image\/(?:jpeg|jpg|png|webp));base64,(.+)$/i,
  );
  if (dataUrlMatch) {
    const safeMimeType = dataUrlMatch[1].toLowerCase().replace('jpg', 'jpeg');
    return {
      dataUrl: `data:${safeMimeType};base64,${dataUrlMatch[2]}`,
      base64Length: dataUrlMatch[2].length,
    };
  }

  const safeMimeType = (mimeType || 'image/jpeg').toLowerCase();
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(safeMimeType)) {
    return null;
  }
  return {
    dataUrl: `data:${safeMimeType};base64,${trimmed}`,
    base64Length: trimmed.length,
  };
}

function cleanOcrText(text: string): string {
  return text
    .replace(/```[\s\S]*?```/g, (block) =>
      block.replace(/```[a-zA-Z]*|```/g, ''),
    )
    .replace(/\r/g, '')
    .split('\n')
    .map((line) => line.replace(/[ \t]+/g, ' ').trim())
    .filter(Boolean)
    .join('\n')
    .trim();
}

export async function analyzeDocument(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.openRouterApiKey) {
    res.status(503).json({ message: 'AI service is not configured' });
    return;
  }

  const { messages } = req.body;
  if (!Array.isArray(messages) || messages.length === 0) {
    res.status(400).json({ message: 'messages is required' });
    return;
  }

  let lastDetail = '';
  for (const model of AI_MODELS) {
    const result = await callOpenRouter(model, messages);
    if (result.ok && result.text) {
      res.json({ result: result.text });
      return;
    }
    lastDetail = result.detail ?? '';
    logger.warn('[analyzeDocument] model failed, trying next', {
      model,
      status: result.status,
      detail: lastDetail,
    });
  }

  res.status(502).json({ message: 'AI service error', detail: lastDetail });
}

export async function recognizeOcrText(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.openRouterApiKey) {
    res.status(503).json({ message: 'AI OCR service is not configured' });
    return;
  }

  const { imageBase64, mimeType } = req.body ?? {};
  if (typeof imageBase64 !== 'string' || imageBase64.trim().length === 0) {
    res.status(400).json({ message: 'imageBase64 is required' });
    return;
  }

  const image = normalizeImagePayload(
    imageBase64,
    typeof mimeType === 'string' ? mimeType : undefined,
  );
  if (!image) {
    res.status(400).json({ message: 'Unsupported image type' });
    return;
  }
  if (image.base64Length > MAX_OCR_IMAGE_BASE64_LENGTH) {
    res.status(413).json({ message: 'Image is too large' });
    return;
  }

  const messages = [
    {
      role: 'system',
      content:
        'You are an OCR engine. Extract only visible text from images. Preserve original languages, capitalization, numbers, and line breaks. Do not translate. Do not explain. Do not infer hidden text. Return plain text only.',
    },
    {
      role: 'user',
      content: [
        {
          type: 'text',
          text:
            'Extract every clearly visible text fragment from this image. The image may contain Russian, English, Romanian, numbers, labels, or packaging text. Preserve line breaks where useful. Return only plain text.',
        },
        { type: 'image_url', image_url: { url: image.dataUrl } },
      ],
    },
  ];

  let lastDetail = '';
  for (const model of OCR_MODELS) {
    const result = await callOpenRouter(model, messages, {
      maxTokens: 1200,
      temperature: 0,
    });
    const text = cleanOcrText(result.text ?? '');
    if (result.ok && text) {
      res.json({ text, provider: 'openrouter', model });
      return;
    }
    lastDetail = result.detail ?? '';
    logger.warn('[recognizeOcrText] model failed, trying next', {
      model,
      status: result.status,
      detail: lastDetail,
    });
  }

  res.status(502).json({ message: 'AI OCR service error', detail: lastDetail });
}
