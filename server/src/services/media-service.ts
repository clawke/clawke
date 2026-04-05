/**
 * 媒体处理核心服务
 *
 * 职责：保存上传原图、生成缩略图、计算 ThumbHash、读取图片尺寸
 */
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { thumbhash } from './thumbhash.js';
import { UPLOAD_DIR, THUMB_DIR } from '../store/clawke-home.js';

// sharp 是可选依赖
let sharp: any;
try {
  sharp = require('sharp');
} catch {
  console.warn('[MediaService] sharp not available, thumbnails/thumbhash disabled');
}

function ensureDirs(): void {
  fs.mkdirSync(UPLOAD_DIR, { recursive: true });
  fs.mkdirSync(THUMB_DIR, { recursive: true });
}

export interface MulterFile {
  originalname: string;
  buffer: Buffer;
  mimetype?: string;
}

/** 保存上传文件（原图） */
export function saveOriginal(multerFile: MulterFile): { filePath: string; fileName: string } {
  ensureDirs();
  const ext = path.extname(multerFile.originalname) || '.bin';
  const baseName = `${Date.now()}_${crypto.randomBytes(4).toString('hex')}${ext}`;
  const filePath = path.join(UPLOAD_DIR, baseName);
  fs.writeFileSync(filePath, multerFile.buffer);
  return { filePath, fileName: baseName };
}

/** 生成缩略图 */
export async function generateThumbnail(originalPath: string, options: { maxWidth?: number } = {}): Promise<string | null> {
  if (!sharp) return null;
  const maxWidth = options.maxWidth || 800;
  const baseName = path.basename(originalPath);
  const thumbName = `thumb_${path.basename(baseName, path.extname(baseName))}.jpg`;
  const thumbPath = path.join(THUMB_DIR, thumbName);
  try {
    await sharp(originalPath)
      .rotate()
      .resize(maxWidth, null, { withoutEnlargement: true })
      .jpeg({ quality: 70 })
      .toFile(thumbPath);
    return thumbPath;
  } catch (e: any) {
    console.warn(`[MediaService] Thumbnail generation failed for ${baseName}: ${e.message}`);
    return null;
  }
}

/** 计算 ThumbHash */
export async function generateThumbHash(imagePath: string): Promise<string | null> {
  if (!sharp) return null;
  try {
    const targetWidth = 100;
    const targetHeight = 100;
    const meta = await sharp(imagePath).metadata();
    const w = meta.width || 1;
    const h = meta.height || 1;
    let resizeW = targetWidth;
    let resizeH = targetHeight;
    if (w > h) {
      resizeH = Math.round(h * targetWidth / w);
    } else if (h > w) {
      resizeW = Math.round(w * targetHeight / h);
    }
    const { data, info } = await sharp(imagePath)
      .rotate()
      .resize(resizeW, resizeH)
      .ensureAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });
    const hash = thumbhash(info.width, info.height, data);
    return Buffer.from(hash).toString('base64');
  } catch (e: any) {
    console.warn(`[MediaService] ThumbHash generation failed: ${e.message}`);
    return null;
  }
}

/** 获取图片尺寸 */
export async function getImageDimensions(imagePath: string): Promise<{ width: number; height: number } | null> {
  if (!sharp) return null;
  try {
    const { info } = await sharp(imagePath)
      .rotate()
      .toBuffer({ resolveWithObject: true });
    return { width: info.width || 0, height: info.height || 0 };
  } catch {
    return null;
  }
}

export interface UploadResult {
  mediaId: string;
  mediaUrl: string;
  mediaType: string;
  thumbUrl: string | null;
  thumbHash: string | null;
  width: number | null;
  height: number | null;
  fileName: string;
  filePath: string;
  isImage: boolean;
}

/** 处理上传的媒体文件：保存 + 缩略图 + ThumbHash + 尺寸 */
export async function processUpload(multerFile: MulterFile): Promise<UploadResult> {
  const { filePath, fileName } = saveOriginal(multerFile);
  const isImage = /\.(jpe?g|png|gif|webp|bmp|tiff?)$/i.test(fileName);
  let thumbUrl: string | null = null;
  let thumbHash: string | null = null;
  let width: number | null = null;
  let height: number | null = null;

  if (isImage) {
    const [thumbPath, hash, dims] = await Promise.all([
      generateThumbnail(filePath),
      generateThumbHash(filePath),
      getImageDimensions(filePath),
    ]);
    if (thumbPath) thumbUrl = `/api/media/thumb/${path.basename(thumbPath)}`;
    thumbHash = hash;
    if (dims) { width = dims.width; height = dims.height; }
  }

  return {
    mediaId: path.basename(fileName, path.extname(fileName)),
    mediaUrl: `/api/media/${fileName}`,
    mediaType: multerFile.mimetype || 'application/octet-stream',
    thumbUrl, thumbHash, width, height, fileName, filePath, isImage,
  };
}

export { UPLOAD_DIR, THUMB_DIR };
