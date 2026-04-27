/**
 * CS Unified Server (HTTP + WebSocket)
 *
 * Express HTTP + WebSocket 统一服务器，单端口。
 * - HTTP: 聊天媒体上传/下载 API
 * - WS:  客户端 WebSocket 连接 (路径 /ws)
 */
import { createServer } from 'http';
import express from 'express';
import { WebSocketServer } from 'ws';
import multer from 'multer';
import { mediaUpload, serveMedia, serveThumbnail } from './routes/media-routes.js';
import { listModels, getModels, getSkills, getConvConfig, putConvConfig } from './routes/config-routes.js';
import { createSkill, deleteSkill, getSkill, listSkillScopes, listSkills, setSkillEnabled, updateSkill } from './routes/skills-routes.js';
import { listGateways, renameGateway } from './routes/gateway-routes.js';
import { listConversations, createConversation, updateConversation, deleteConversation } from './routes/conversation-routes.js';
import {
  createTask,
  deleteTask,
  getTask,
  getTaskRunOutput,
  listTaskRuns,
  listTasks,
  runTask,
  setTaskEnabled,
  updateTask,
} from './routes/tasks-routes.js';
import { loadConfig } from './config.js';
import type { Server } from 'http';

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

export function isLoopbackAddress(remoteAddress?: string | null): boolean {
  if (!remoteAddress) return false;
  const address = remoteAddress.trim().toLowerCase();
  if (address === '::1') return true;
  if (address.startsWith('127.')) return true;
  if (address.startsWith('::ffff:127.')) return true;
  return false;
}

export function isAuthorizedRequest({
  serverToken,
  clientToken,
  remoteAddress,
}: {
  serverToken: string;
  clientToken: string;
  remoteAddress?: string | null;
}): boolean {
  if (isLoopbackAddress(remoteAddress)) return true;
  return serverToken === clientToken;
}

export function startUnifiedServer(port: number = 8780): { server: Server; wss: WebSocketServer } {
  const config = loadConfig();
  const app = express();
  const server = createServer(app);

  const serverToken = config.relay?.token || '';
  const wss = new WebSocketServer({
    server,
    path: '/ws',
    maxPayload: 50 * 1024 * 1024,
    verifyClient: ({ req }: any, cb: (result: boolean, code?: number, message?: string) => void) => {
      const url = new URL(req.url, `http://${req.headers.host}`);
      const queryToken = url.searchParams.get('token') || '';
      const headerToken = (req.headers.authorization || '').replace('Bearer ', '');
      const clientToken = queryToken || headerToken;

      if (!isAuthorizedRequest({
        serverToken,
        clientToken,
        remoteAddress: req.socket.remoteAddress,
      })) {
        const cMask = clientToken ? clientToken.slice(0, 8) + '...' : '(empty)';
        const sMask = serverToken ? serverToken.slice(0, 8) + '...' : '(empty)';
        console.warn(`[WS] 🔒 Connection rejected: token mismatch (client=${cMask}, expected=${sMask})`);
        cb(false, 401, 'Unauthorized');
        return;
      }
      cb(true);
    },
  });

  app.use(express.json({ limit: '1mb' }));

  // CORS
  app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') {
      res.sendStatus(200);
      return;
    }
    next();
  });

  // API 服务根路径说明，避免浏览器直开时显示 Express 默认的 Cannot GET /。
  app.get('/', (_req, res) => {
    res.json({
      service: 'clawke-cs',
      kind: 'api',
      message: 'Clawke HTTP server is an API service. Open the Flutter app for the product UI, or docs/ui-preview.html for the static preview.',
      endpoints: [
        '/health',
        '/api/gateways',
        '/api/models',
        '/api/skills',
        '/api/config/skills',
        '/api/config/models',
        '/api/conversations',
      ],
    });
  });

  // Token 认证中间件
  app.use((req, res, next) => {
    if (req.path === '/health') return next();
    const clientToken = (req.headers.authorization || '').replace('Bearer ', '');
    if (!isAuthorizedRequest({
      serverToken,
      clientToken,
      remoteAddress: req.socket.remoteAddress,
    })) {
      console.warn(`[HTTP] 🔒 Unauthorized: ${req.method} ${req.originalUrl} (token mismatch)`);
      res.status(401).json({ error: 'unauthorized' });
      return;
    }
    next();
  });

  // Request logging
  app.use((req, res, next) => {
    const start = Date.now();
    res.on('finish', () => {
      const ms = Date.now() - start;
      console.log(`[HTTP] ${req.method} ${req.originalUrl} → ${res.statusCode} (${ms}ms)`);
    });
    next();
  });

  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: MAX_FILE_SIZE },
  });

  // 媒体 API
  app.post('/api/media/upload', upload.single('file'), mediaUpload as any);
  app.get('/api/media/thumb/:filename', serveThumbnail as any);
  app.get('/api/media/:filename', serveMedia as any);

  // Health check
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', service: 'clawke-cs', timestamp: Date.now() });
  });

  app.get('/', (_req, res) => {
    res.json({
      service: 'clawke-cs',
      endpoints: [
        '/health',
        '/api/media/upload',
        '/api/media/:filename',
        '/api/gateways',
        '/api/models',
        '/api/config/models',
        '/api/config/skills',
        '/api/conversations',
        '/api/tasks',
      ],
    });
  });

  // 会话配置 API
  app.get('/api/models', listModels as any);
  app.get('/api/config/models', getModels as any);
  app.get('/api/config/skills', getSkills as any);
  app.get('/api/conv/:id/config', getConvConfig as any);
  app.put('/api/conv/:id/config', putConvConfig as any);

  // Skills 管理 API
  app.get('/api/gateways', listGateways as any);
  app.patch('/api/gateways/:gatewayId', renameGateway as any);

  // Skills 管理 API
  app.get('/api/skills/scopes', listSkillScopes as any);
  app.get('/api/skills', listSkills as any);
  app.get('/api/skills/:category/:name', getSkill as any);
  app.post('/api/skills', createSkill as any);
  app.put('/api/skills/:category/:name/enabled', setSkillEnabled as any);
  app.put('/api/skills/:category/:name', updateSkill as any);
  app.delete('/api/skills/:category/:name', deleteSkill as any);

  // 会话 CRUD API
  app.get('/api/conversations', listConversations as any);
  app.post('/api/conversations', createConversation as any);
  app.put('/api/conversations/:id', updateConversation as any);
  app.delete('/api/conversations/:id', deleteConversation as any);

  // 任务管理 API
  app.get('/api/tasks', listTasks as any);
  app.get('/api/tasks/:taskId', getTask as any);
  app.post('/api/tasks', createTask as any);
  app.put('/api/tasks/:taskId/enabled', setTaskEnabled as any);
  app.post('/api/tasks/:taskId/run', runTask as any);
  app.get('/api/tasks/:taskId/runs', listTaskRuns as any);
  app.get('/api/tasks/:taskId/runs/:runId/output', getTaskRunOutput as any);
  app.put('/api/tasks/:taskId', updateTask as any);
  app.delete('/api/tasks/:taskId', deleteTask as any);

  // Error handler
  app.use((err: any, _req: any, res: any, _next: any) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(413).json({ error: `File too large (max ${MAX_FILE_SIZE / 1024 / 1024}MB)` });
      }
      return res.status(400).json({ error: err.message });
    }
    console.error('[HTTP] Unhandled error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  });

  server.listen(port, '127.0.0.1', () => {
    console.log(`[Server] 📂 Unified Server on http://127.0.0.1:${port}`);
    console.log(`[Server]    HTTP: /api/media/upload, /api/media/:filename, /api/tasks, /health`);
    console.log(`[Server]    WS:   ws://127.0.0.1:${port}/ws`);
  });

  return { server, wss };
}
