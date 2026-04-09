/**
 * STT Route — 语音转文字 (Google Cloud Speech-to-Text)
 *
 * 接收音频文件，调用 Google Cloud STT API 转写，返回文本。
 * POST /api/stt  (multipart/form-data, field: "audio")
 */
import type { Request, Response } from 'express';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

function loadGoogleSttKey(): string {
  // 1. 环境变量优先
  if (process.env.GOOGLE_STT_KEY) return process.env.GOOGLE_STT_KEY;

  // 2. 从 ~/.clawke/clawke.json 读取
  try {
    const configPath = path.join(os.homedir(), '.clawke', 'clawke.json');
    const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    if (config.stt?.googleApiKey) return config.stt.googleApiKey;
  } catch {}

  return '';
}

const GOOGLE_STT_KEY = loadGoogleSttKey();
const GOOGLE_STT_URL = 'https://speech.googleapis.com/v1/speech:recognize';

export async function sttTranscribe(req: Request, res: Response) {
  if (!GOOGLE_STT_KEY) {
    console.error('[STT] ❌ GOOGLE_STT_KEY not configured');
    return res.status(500).json({ error: 'STT not configured: missing GOOGLE_STT_KEY' });
  }

  const file = (req as any).file;
  if (!file) {
    return res.status(400).json({ error: 'No audio file provided' });
  }

  console.log(`[STT] 🎤 Received audio: ${file.originalname} (${(file.size / 1024).toFixed(1)}KB, ${file.mimetype})`);

  try {
    const audioContent = file.buffer.toString('base64');

    const requestBody = {
      config: {
        encoding: 'LINEAR16',
        sampleRateHertz: 16000,
        languageCode: 'zh-CN',
        alternativeLanguageCodes: ['en-US'],
        model: 'default',
        enableAutomaticPunctuation: true,
      },
      audio: {
        content: audioContent,
      },
    };

    const startTime = Date.now();

    const response = await fetch(`${GOOGLE_STT_URL}?key=${GOOGLE_STT_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(requestBody),
    });

    const elapsed = Date.now() - startTime;

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`[STT] ❌ Google STT error (${response.status}): ${errorText}`);
      return res.status(502).json({ error: `Google STT error: ${response.status}`, detail: errorText });
    }

    const result = await response.json() as any;

    // Google STT 返回结构: { results: [{ alternatives: [{ transcript, confidence }] }] }
    const transcript = result.results
      ?.map((r: any) => r.alternatives?.[0]?.transcript || '')
      .join('') || '';

    console.log(`[STT] ✅ Transcribed in ${elapsed}ms: "${transcript}"`);
    return res.json({ text: transcript, elapsed });
  } catch (error: any) {
    console.error('[STT] ❌ Transcription failed:', error.message);
    return res.status(500).json({ error: error.message });
  }
}
