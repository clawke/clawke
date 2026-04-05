/**
 * 免鉴权媒体下载服务
 *
 * 独立 HTTP 服务器，仅提供媒体文件下载（GET），不需要 token。
 * 用于局域网 / SSH 隧道场景，供 Gateway 直接下载媒体文件。
 */
import express from 'express';
import { createServer } from 'http';
import type { Server } from 'http';
import { serveMedia, serveThumbnail } from './routes/media-routes.js';

export function startMediaServer(port: number = 8781): Server {
  const app = express();

  app.use((_req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    if (_req.method === 'OPTIONS') {
      res.sendStatus(200);
      return;
    }
    next();
  });

  app.get('/api/media/thumb/:filename', serveThumbnail as any);
  app.get('/api/media/:filename', serveMedia as any);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', service: 'clawke-media', timestamp: Date.now() });
  });

  const server = createServer(app);
  server.listen(port, () => {
    console.log(`[Server] 📂 Media Server on http://127.0.0.1:${port} (no auth)`);
    console.log(`[Server]    GET /api/media/:filename, /api/media/thumb/:filename`);
  });

  return server;
}
