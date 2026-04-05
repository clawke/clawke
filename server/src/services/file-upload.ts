/**
 * 文件上传处理服务
 *
 * 处理 CUP 消息中的 base64/mediaUrl 附件，保存到本地，生成媒体元数据。
 */
import fs from 'fs';
import os from 'os';
import path from 'path';
import { UPLOAD_DIR } from '../store/clawke-home.js';
import { generateThumbnail, generateThumbHash, getImageDimensions } from './media-service.js';
import { loadConfig } from '../config.js';

const config = loadConfig();
const MAX_BASE64_SIZE = 15 * 1024 * 1024;
const SHARED_FS = config.openclaw?.sharedFs !== false;
const MEDIA_PORT = config.server.mediaPort || 8781;

/** 获取 CS 媒体服务的对外可达 base URL */
export function getHttpBaseUrl(): string {
  const mediaBaseUrl = config.openclaw?.mediaBaseUrl;
  if (mediaBaseUrl) {
    return mediaBaseUrl.replace(/\/$/, '');
  }
  const host = _detectLanIp() || '127.0.0.1';
  return `http://${host}:${MEDIA_PORT}`;
}

function _detectLanIp(): string | null {
  const interfaces = os.networkInterfaces();
  for (const name in interfaces) {
    for (const iface of interfaces[name]!) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return null;
}

/** 确保上传目录存在 */
export function ensureUploadDir(): void {
  if (!fs.existsSync(UPLOAD_DIR)) {
    fs.mkdirSync(UPLOAD_DIR, { recursive: true });
    console.log(`[Server] Created upload directory: ${UPLOAD_DIR}`);
  }
}

function generateTempName(ext: string): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  const date = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}`;
  const time = `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`;
  const rand = Math.random().toString(36).slice(2, 6);
  return `${date}_${time}_${rand}${ext}`;
}

/** 将 Base64 字符串解码并保存到 uploads/ 目录 */
export function saveBase64File(base64Data: string, fileName: string): { filePath: string; size: number } {
  if (!base64Data || typeof base64Data !== 'string') {
    throw new Error('Invalid base64 data');
  }
  if (base64Data.length > MAX_BASE64_SIZE) {
    throw new Error(`File too large: base64 length ${base64Data.length} exceeds limit ${MAX_BASE64_SIZE}`);
  }
  ensureUploadDir();
  const ext = path.extname(fileName || '.dat');
  const destName = generateTempName(ext);
  const destPath = path.join(UPLOAD_DIR, destName);
  const buffer = Buffer.from(base64Data, 'base64');
  fs.writeFileSync(destPath, buffer);
  console.log(`[Server] 📁 File saved: ${destPath} (${buffer.length} bytes)`);
  return { filePath: destPath, size: buffer.length };
}

export interface MediaResult {
  mediaPaths: string[];
  mediaTypes: string[];
  fileNames: string[];
  mediaRelativeUrls?: string[];
  csHttpBase?: string;
}

/** 处理 user_message 中的 base64/mediaUrl attachments */
export async function processMessageMedia(data: Record<string, any>): Promise<MediaResult | null> {
  if (!data) return null;

  const type = data.type || 'text';
  const mediaPaths: string[] = [];
  const mediaTypes: string[] = [];
  const fileNames: string[] = [];

  if (type === 'image' && data.base64) {
    const origBase64 = data.base64;
    const fileName = data.fileName || 'image.png';
    const { filePath } = saveBase64File(origBase64, fileName);
    data.content = filePath;
    delete data.base64;
    mediaPaths.push(filePath);
    mediaTypes.push(data.mediaType || 'image/png');
    if (!SHARED_FS) fileNames.push(fileName);
    data.mediaUrl = `/api/media/${path.basename(filePath)}`;
    await _generateMediaMetaAsync(filePath, data);

  } else if (type === 'image' && data.mediaUrl) {
    const basename = path.basename(data.mediaUrl);
    const filePath = path.join(UPLOAD_DIR, basename);
    mediaPaths.push(filePath);
    mediaTypes.push(data.mediaType || 'image/png');
    fileNames.push(data.fileName || basename);

  } else if (type === 'file' && data.base64) {
    const origBase64 = data.base64;
    const fileName = data.fileName || 'file';
    const { filePath, size } = saveBase64File(origBase64, fileName);
    data.content = JSON.stringify({ path: filePath, name: fileName, size });
    delete data.base64;
    mediaPaths.push(filePath);
    mediaTypes.push(data.mediaType || 'application/octet-stream');
    if (!SHARED_FS) fileNames.push(fileName);

  } else if (type === 'file' && data.mediaUrl) {
    const basename = path.basename(data.mediaUrl);
    const filePath = path.join(UPLOAD_DIR, basename);
    mediaPaths.push(filePath);
    mediaTypes.push(data.mediaType || 'application/octet-stream');
    fileNames.push(data.fileName || basename);

  } else if (type === 'mixed' && data.content) {
    try {
      const mixed = typeof data.content === 'string' ? JSON.parse(data.content) : data.content;
      const attachments = mixed.attachments || [];
      for (const att of attachments) {
        if (att.mediaUrl) {
          const basename = path.basename(att.mediaUrl);
          const filePath = path.join(UPLOAD_DIR, basename);
          mediaPaths.push(filePath);
          mediaTypes.push(att.mediaType || (att.type === 'image' ? 'image/png' : 'application/octet-stream'));
          fileNames.push(att.name || att.fileName || basename);
        } else if (att.base64) {
          const origBase64 = att.base64;
          const fileName = att.name || att.fileName || 'file';
          const { filePath, size } = saveBase64File(origBase64, fileName);
          att.path = filePath;
          att.size = size;
          delete att.base64;
          mediaPaths.push(filePath);
          mediaTypes.push(att.mediaType || (att.type === 'image' ? 'image/png' : 'application/octet-stream'));
          if (!SHARED_FS) fileNames.push(fileName);
        }
      }
      data.content = JSON.stringify(mixed);
    } catch (e: any) {
      console.error('[Server] Failed to process mixed attachments:', e.message);
    }
  }

  if (mediaPaths.length === 0) return null;

  const result: MediaResult = { mediaPaths, mediaTypes, fileNames };
  result.mediaRelativeUrls = mediaPaths.map(p => `/api/media/${path.basename(p)}`);
  result.csHttpBase = getHttpBaseUrl();
  return result;
}

async function _generateMediaMetaAsync(filePath: string, data: Record<string, any>): Promise<void> {
  try {
    const [thumbPath, hash, dims] = await Promise.all([
      generateThumbnail(filePath),
      generateThumbHash(filePath),
      getImageDimensions(filePath),
    ]);
    if (thumbPath) data.thumbUrl = `/api/media/thumb/${path.basename(thumbPath)}`;
    if (hash) data.thumbHash = hash;
    if (dims) { data.width = dims.width; data.height = dims.height; }
  } catch {
    // 非图片或 sharp 不可用时静默忽略
  }
}

export { UPLOAD_DIR };
