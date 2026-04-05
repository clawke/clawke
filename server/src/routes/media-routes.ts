/**
 * 聊天媒体 REST API
 *
 * POST /api/media/upload       - 上传图片/文件
 * GET  /api/media/:filename    - 获取原图/文件
 * GET  /api/media/thumb/:filename - 获取缩略图
 */
import path from 'path';
import fs from 'fs';
import type { Request, Response } from 'express';
import { processUpload, UPLOAD_DIR, THUMB_DIR } from '../services/media-service.js';
import { isFilenameSafe } from '../services/path-security.js';

/** POST /api/media/upload */
export async function mediaUpload(req: Request, res: Response): Promise<void> {
  try {
    const file = (req as any).file;
    if (!file) {
      res.status(400).json({ error: 'No file provided' });
      return;
    }
    const result = await processUpload(file);
    console.log(`[MediaRoutes] Upload: ${result.fileName} (image=${result.isImage}, thumbHash=${!!result.thumbHash})`);
    res.json({
      mediaId: result.mediaId,
      mediaUrl: result.mediaUrl,
      mediaType: result.mediaType,
      thumbUrl: result.thumbUrl,
      thumbHash: result.thumbHash,
      width: result.width,
      height: result.height,
    });
  } catch (e: any) {
    console.error('[MediaRoutes] Upload failed:', e.message);
    res.status(500).json({ error: 'Upload failed' });
  }
}

/** GET /api/media/:filename */
export function serveMedia(req: Request, res: Response): void {
  const filename = req.params.filename as string;
  if (!isFilenameSafe(filename)) {
    res.status(400).json({ error: 'Invalid filename' });
    return;
  }
  const filePath = path.join(UPLOAD_DIR, filename);
  if (!fs.existsSync(filePath)) {
    res.status(404).json({ error: 'File not found' });
    return;
  }
  res.sendFile(filePath);
}

/** GET /api/media/thumb/:filename */
export function serveThumbnail(req: Request, res: Response): void {
  const filename = req.params.filename as string;
  if (!isFilenameSafe(filename)) {
    res.status(400).json({ error: 'Invalid filename' });
    return;
  }
  const filePath = path.join(THUMB_DIR, filename);
  if (!fs.existsSync(filePath)) {
    const originalName = filename.replace(/^thumb_/, '').replace(/\.jpg$/, '');
    const files = fs.readdirSync(UPLOAD_DIR);
    const match = files.find(f => f.startsWith(originalName));
    if (match) {
      res.sendFile(path.join(UPLOAD_DIR, match));
      return;
    }
    res.status(404).json({ error: 'Thumbnail not found' });
    return;
  }
  res.sendFile(filePath);
}
