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

const REPLICATE_API = 'https://api.replicate.com/v1';
const RESTORE_POLL_INTERVAL_MS = 2000;
const TRANSCRIBE_TIMEOUT_MS = 180_000;
// BOPBTL с HR/scratch считается ~46с (+ холодный старт) — даём запас.
const RESTORE_TIMEOUT_MS = 150_000;

/**
 * Поля input у разных моделей восстановления различаются — собираем под
 * конкретную модель. По умолчанию это BOPBTL (удаление царапин + HR).
 */
function buildRestoreInput(
  model: string,
  imageDataUrl: string,
): Record<string, unknown> {
  const m = model.toLowerCase();
  if (m.includes('gfpgan')) {
    return { img: imageDataUrl, version: 'v1.4', scale: 2 };
  }
  if (m.includes('codeformer')) {
    return {
      image: imageDataUrl,
      // Ближе к 1 = вернее оригиналу (меньше «галлюцинаций» лица).
      codeformer_fidelity: 0.9,
      background_enhance: true,
      face_upsample: true,
      upscale: 2,
    };
  }
  // microsoft/bringing-old-photos-back-to-life и совместимые:
  // with_scratch — детекция и инпейнтинг царапин; HR — режим высокого
  // разрешения (качественнее, но дольше).
  return { image: imageDataUrl, HR: true, with_scratch: true };
}

interface ReplicatePrediction {
  id?: string;
  status?: string; // starting | processing | succeeded | failed | canceled
  output?: unknown;
  error?: unknown;
  detail?: string;
  urls?: { get?: string };
  latest_version?: { id?: string }; // приходит в ответе GET /models/{model}
}

/** Универсальный JSON-вызов к Replicate (https, без сторонних зависимостей). */
function replicateRequest(
  method: string,
  urlStr: string,
  body?: unknown,
  extraHeaders: Record<string, string> = {},
): Promise<{ status: number; json: ReplicatePrediction | null; raw: string }> {
  return new Promise((resolve) => {
    const url = new URL(urlStr);
    const payload = body ? JSON.stringify(body) : undefined;
    const proxyReq = https.request(
      {
        method,
        hostname: url.hostname,
        path: url.pathname + url.search,
        port: 443,
        headers: {
          Authorization: `Bearer ${env.replicateApiToken}`,
          'Content-Type': 'application/json',
          ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
          ...extraHeaders,
        },
      },
      (proxyRes) => {
        let data = '';
        proxyRes.on('data', (chunk) => {
          data += chunk;
        });
        proxyRes.on('end', () => {
          let json: ReplicatePrediction | null = null;
          try {
            json = JSON.parse(data);
          } catch {
            json = null;
          }
          resolve({ status: proxyRes.statusCode ?? 0, json, raw: data });
        });
      },
    );
    proxyReq.on('error', (err) => {
      logger.error('[replicateRequest] request error', { err });
      resolve({ status: 0, json: null, raw: '' });
    });
    if (payload) proxyReq.write(payload);
    proxyReq.end();
  });
}

const delay = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Вход для модели-уточнителя (2-я стадия). На вход идёт URL результата 1-й
 * стадии (Replicate принимает http-URL как файловый вход).
 */
function buildRefineInput(
  model: string,
  imageUrl: string,
  fidelity: number,
): Record<string, unknown> {
  const m = model.toLowerCase();
  if (m.includes('codeformer')) {
    return {
      image: imageUrl,
      // Ближе к 1 = вернее лицам, меньше «кукольности». Приходит из приложения
      // («Естественно ↔ Чётче») либо из env по умолчанию.
      codeformer_fidelity: fidelity,
      background_enhance: true, // Real-ESRGAN для фона/деталей
      face_upsample: true, // повышает чёткость лиц
      upscale: 2,
    };
  }
  if (m.includes('gfpgan')) {
    return { img: imageUrl, version: 'v1.4', scale: 2 };
  }
  // Real-ESRGAN и совместимые апскейлеры.
  return { image: imageUrl, scale: 2 };
}

type ModelRun =
  | { ok: true; url: string }
  | { ok: false; status: number; detail: string };

/**
 * Прогоняет одну модель Replicate: версия модели → создание предсказания →
 * поллинг до готовности (в рамках общего [deadline]) → URL результата.
 * Community-модели требуют version-хэш на /v1/predictions, поэтому сперва
 * GET модели.
 */
async function runReplicateModel(
  model: string,
  input: Record<string, unknown>,
  deadline: number,
): Promise<ModelRun> {
  const modelInfo = await replicateRequest(
    'GET',
    `${REPLICATE_API}/models/${model}`,
  );
  if (modelInfo.status !== 200) {
    return {
      ok: false,
      status: 502,
      detail: modelInfo.json?.detail ?? modelInfo.raw.slice(0, 300),
    };
  }
  const versionId = modelInfo.json?.latest_version?.id;
  const hasVersion = typeof versionId === 'string' && versionId.length > 0;

  const created = await replicateRequest(
    'POST',
    hasVersion
      ? `${REPLICATE_API}/predictions`
      : `${REPLICATE_API}/models/${model}/predictions`,
    hasVersion ? { version: versionId, input } : { input },
    { Prefer: 'wait' },
  );
  if (created.status !== 200 && created.status !== 201) {
    return {
      ok: false,
      status: 502,
      detail: created.json?.detail ?? created.raw.slice(0, 300),
    };
  }

  let prediction: ReplicatePrediction = created.json ?? {};
  const getUrl = prediction.urls?.get;
  const terminal = ['succeeded', 'failed', 'canceled'];
  while (
    getUrl &&
    !terminal.includes(prediction.status ?? '') &&
    Date.now() < deadline
  ) {
    await delay(RESTORE_POLL_INTERVAL_MS);
    const poll = await replicateRequest('GET', getUrl);
    if (poll.json) prediction = poll.json;
  }

  if (prediction.status !== 'succeeded') {
    return {
      ok: false,
      status: 502,
      detail: String(prediction.error ?? prediction.status ?? 'timeout'),
    };
  }
  const output = Array.isArray(prediction.output)
    ? prediction.output[0]
    : prediction.output;
  if (typeof output !== 'string' || output.length === 0) {
    return { ok: false, status: 502, detail: 'unexpected output' };
  }
  return { ok: true, url: output };
}

type TranscriptionRun =
  | { ok: true; text: string; language?: string }
  | { ok: false; status: number; detail: string };

function transcriptionFromOutput(
  output: unknown,
): { text: string; language?: string } | null {
  if (typeof output === 'string') {
    const text = output.trim();
    return text ? { text } : null;
  }
  if (!output || typeof output !== 'object' || Array.isArray(output)) {
    return null;
  }

  const result = output as Record<string, unknown>;
  const directText = [result.transcription, result.text].find(
    (value): value is string =>
      typeof value === 'string' && value.trim().length > 0,
  );
  let text = directText?.trim() ?? '';
  if (!text && Array.isArray(result.segments)) {
    text = result.segments
      .map((segment) => {
        if (!segment || typeof segment !== 'object') return '';
        const value = (segment as Record<string, unknown>).text;
        return typeof value === 'string' ? value.trim() : '';
      })
      .filter(Boolean)
      .join(' ')
      .trim();
  }
  if (!text) return null;

  const languageValue = result.detected_language ?? result.language;
  const language =
    typeof languageValue === 'string' && languageValue.trim()
      ? languageValue.trim()
      : undefined;
  return { text, ...(language ? { language } : {}) };
}

async function runReplicateTranscription(
  model: string,
  audioDataUrl: string,
): Promise<TranscriptionRun> {
  const modelInfo = await replicateRequest(
    'GET',
    `${REPLICATE_API}/models/${model}`,
  );
  if (modelInfo.status !== 200) {
    return {
      ok: false,
      status: 502,
      detail: modelInfo.json?.detail ?? modelInfo.raw.slice(0, 300),
    };
  }

  const versionId = modelInfo.json?.latest_version?.id;
  const hasVersion = typeof versionId === 'string' && versionId.length > 0;
  const input = {
    audio: audioDataUrl,
    model: 'large-v3',
    translate: false,
    transcription: 'plain text',
  };
  const created = await replicateRequest(
    'POST',
    hasVersion
      ? `${REPLICATE_API}/predictions`
      : `${REPLICATE_API}/models/${model}/predictions`,
    hasVersion ? { version: versionId, input } : { input },
    { Prefer: 'wait' },
  );
  if (created.status !== 200 && created.status !== 201) {
    return {
      ok: false,
      status: 502,
      detail: created.json?.detail ?? created.raw.slice(0, 300),
    };
  }

  let prediction: ReplicatePrediction = created.json ?? {};
  const getUrl = prediction.urls?.get;
  const terminal = ['succeeded', 'failed', 'canceled'];
  const deadline = Date.now() + TRANSCRIBE_TIMEOUT_MS;
  while (
    getUrl &&
    !terminal.includes(prediction.status ?? '') &&
    Date.now() < deadline
  ) {
    await delay(RESTORE_POLL_INTERVAL_MS);
    const poll = await replicateRequest('GET', getUrl);
    if (poll.json) prediction = poll.json;
  }

  if (prediction.status !== 'succeeded') {
    const timedOut = Date.now() >= deadline;
    return {
      ok: false,
      status: timedOut ? 504 : 502,
      detail: String(
        prediction.error ?? (timedOut ? 'timeout' : prediction.status),
      ),
    };
  }

  const transcription = transcriptionFromOutput(prediction.output);
  if (!transcription) {
    return { ok: false, status: 422, detail: 'No speech recognized' };
  }
  return { ok: true, ...transcription };
}

function normalizedAudioMime(file: Express.Multer.File): string {
  if (file.mimetype.startsWith('audio/')) return file.mimetype;
  const name = file.originalname.toLowerCase();
  if (name.endsWith('.m4a') || name.endsWith('.mp4')) return 'audio/mp4';
  if (name.endsWith('.mp3')) return 'audio/mpeg';
  if (name.endsWith('.wav')) return 'audio/wav';
  if (name.endsWith('.ogg')) return 'audio/ogg';
  if (name.endsWith('.webm')) return 'audio/webm';
  return 'audio/aac';
}

export async function transcribeVoiceNote(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.replicateApiToken) {
    res.status(503).json({ message: 'Transcription service is not configured' });
    return;
  }
  const file = req.file;
  if (!file?.buffer?.length) {
    res.status(400).json({ message: 'Audio file is required' });
    return;
  }

  const mimeType = normalizedAudioMime(file);
  const audioDataUrl = `data:${mimeType};base64,${file.buffer.toString('base64')}`;
  const result = await runReplicateTranscription(
    env.replicateTranscribeModel,
    audioDataUrl,
  );
  if (!result.ok) {
    logger.warn('[transcribeVoiceNote] transcription failed', {
      model: env.replicateTranscribeModel,
      status: result.status,
      detail: result.detail,
    });
    res.status(result.status).json({
      message:
        result.status === 422
          ? 'No speech recognized'
          : 'Transcription failed',
      detail: result.detail,
    });
    return;
  }

  res.json({
    text: result.text,
    language: result.language,
    provider: 'replicate',
    model: env.replicateTranscribeModel,
  });
}

/**
 * Rebuilds masked areas with a semantic inpainting model. Unlike the old
 * client-side texture copy, this can continue mountains, clouds and buildings
 * through translucent repeated text without creating rectangular patches.
 */
export async function removeWatermarks(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.replicateApiToken) {
    res.status(503).json({ message: 'Inpainting service is not configured' });
    return;
  }

  const { imageBase64, imageMimeType, maskBase64 } = req.body ?? {};
  if (
    typeof imageBase64 !== 'string' ||
    imageBase64.trim().length === 0 ||
    typeof maskBase64 !== 'string' ||
    maskBase64.trim().length === 0
  ) {
    res.status(400).json({ message: 'imageBase64 and maskBase64 are required' });
    return;
  }

  const image = normalizeImagePayload(
    imageBase64,
    typeof imageMimeType === 'string' ? imageMimeType : undefined,
  );
  const mask = normalizeImagePayload(maskBase64, 'image/png');
  if (!image || !mask) {
    res.status(400).json({ message: 'Unsupported image type' });
    return;
  }
  if (
    image.base64Length > MAX_OCR_IMAGE_BASE64_LENGTH ||
    mask.base64Length > MAX_OCR_IMAGE_BASE64_LENGTH
  ) {
    res.status(413).json({ message: 'Image is too large' });
    return;
  }

  const result = await runReplicateModel(
    env.replicateInpaintModel,
    {
      image: image.dataUrl,
      mask: mask.dataUrl,
      prompt:
        'Remove all text, logos, and watermark marks inside the white mask. ' +
        'Seamlessly reconstruct the original natural background, preserving ' +
        'the composition, colors, lighting, perspective, and details outside the mask.',
      output_format: 'jpg',
    },
    Date.now() + RESTORE_TIMEOUT_MS,
  );

  if (!result.ok) {
    logger.warn('[removeWatermarks] inpainting failed', {
      model: env.replicateInpaintModel,
      detail: result.detail,
    });
    res
      .status(result.status)
      .json({ message: 'Inpainting failed', detail: result.detail });
    return;
  }

  res.json({ url: result.url });
}

/**
 * Удаление водяного знака со ВСЕГО кадра без маски — инструкционный редактор
 * (FLUX Kontext). В отличие от маски-инпейнтинга справляется со сплошными /
 * тайловыми знаками, перекрывающими всю картинку.
 */
export async function dewatermarkImage(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.replicateApiToken) {
    res.status(503).json({ message: 'Dewatermark service is not configured' });
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

  const result = await runReplicateModel(
    env.replicateDewatermarkModel,
    {
      prompt:
        'Remove all watermarks, text overlays, stamps, and logos from the ' +
        'image, including repeated diagonal watermark tiles. Reconstruct the ' +
        'underlying scene naturally and keep every other detail, color, ' +
        'lighting, perspective, and composition exactly the same.',
      input_image: image.dataUrl,
      output_format: 'jpg',
    },
    Date.now() + RESTORE_TIMEOUT_MS,
  );

  if (!result.ok) {
    logger.warn('[dewatermarkImage] failed', {
      model: env.replicateDewatermarkModel,
      detail: result.detail,
    });
    res
      .status(result.status)
      .json({ message: 'Dewatermark failed', detail: result.detail });
    return;
  }

  res.json({ url: result.url });
}

/**
 * Восстановление старого фото в две стадии:
 *   1) удаление дефектов (BOPBTL: царапины/трещины + аккуратная реставрация);
 *   2) уточнение (CodeFormer: чёткость лиц + апскейл/детали, fidelity 0.7).
 * Если 2-я стадия не задана/упала — отдаём результат 1-й.
 */
export async function restorePhoto(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  if (!env.replicateApiToken) {
    res.status(503).json({ message: 'Restore service is not configured' });
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

  // Сила восстановления из приложения («Естественно ↔ Чётче» → fidelity).
  // Невалидное/отсутствующее значение → дефолт из env.
  const bodyFidelity = (req.body as { fidelity?: unknown })?.fidelity;
  const fidelity =
    typeof bodyFidelity === 'number' && bodyFidelity >= 0 && bodyFidelity <= 1
      ? bodyFidelity
      : env.replicateCodeformerFidelity;

  // Общий бюджет времени на обе стадии (держим HTTP-соединение открытым).
  const deadline = Date.now() + RESTORE_TIMEOUT_MS;

  // Стадия 1 — удаление дефектов (BOPBTL). Критична: при провале возвращаем
  // ошибку, приложение откатится на локальное улучшение.
  const stage1 = await runReplicateModel(
    env.replicateRestoreModel,
    buildRestoreInput(env.replicateRestoreModel, image.dataUrl),
    deadline,
  );
  if (!stage1.ok) {
    logger.warn('[restorePhoto] stage1 failed', {
      model: env.replicateRestoreModel,
      detail: stage1.detail,
    });
    res
      .status(stage1.status)
      .json({ message: 'Restore failed', detail: stage1.detail });
    return;
  }

  let finalUrl = stage1.url;

  // Стадия 2 — уточнение (CodeFormer): чёткость лиц + апскейл/детали.
  // Некритична: если упадёт/таймаутнет — отдаём результат 1-й стадии.
  // Пропускаем, если refine-модель не задана, совпадает со стадией 1, или
  // бюджет времени уже исчерпан.
  const refineModel = env.replicateRefineModel;
  if (
    refineModel &&
    refineModel.toLowerCase() !== env.replicateRestoreModel.toLowerCase() &&
    Date.now() < deadline
  ) {
    const stage2 = await runReplicateModel(
      refineModel,
      buildRefineInput(refineModel, finalUrl, fidelity),
      deadline,
    );
    if (stage2.ok) {
      finalUrl = stage2.url;
    } else {
      logger.warn('[restorePhoto] refine stage failed, using stage1', {
        model: refineModel,
        detail: stage2.detail,
      });
    }
  }

  res.json({ url: finalUrl });
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
