/**
 * Clawke Server 入口 — 依赖组装 + 启动
 *
 * 职责：创建实例 → 组装依赖 → 启动 server → 注册信号处理
 * 规则：只做 new + 传参 + start，不含业务逻辑
 */
import * as path from 'path';
import * as fs from 'fs';
import * as os from 'os';
import { loadConfig, getConfigPath } from './config.js';
import { ensureDirectories, DATA_DIR } from './store/clawke-home.js';
import { Database } from './store/database.js';
import { MessageStore } from './store/message-store.js';
import { ConversationStore } from './store/conversation-store.js';
import { ConversationConfigStore } from './store/conversation-config-store.js';
import { CupV2Handler } from './protocol/cup-v2-handler.js';
import { StatsCollector } from './services/stats-collector.js';
import { VersionChecker } from './services/version-checker.js';
import { EventRegistry } from './event-registry.js';
import { MessageRouter } from './upstream/message-router.js';
import { ActionRouter, createUserActionHandler } from './event-handlers/user-action.js';
import { createUserMessageHandler } from './event-handlers/user-message.js';
import { createSyncHandler } from './event-handlers/sync.js';
import { createCheckUpdateHandler } from './event-handlers/check-update.js';
import { createAbortHandler } from './event-handlers/abort.js';
import { createDashboardHandler } from './event-handlers/request-dashboard.js';
import { createPingHandler } from './event-handlers/ping.js';
import { translateToCup } from './translator/cup-encoder.js';

import { startClientServer, broadcastToClients, sendToClient } from './downstream/client-server.js';
import { startUnifiedServer } from './http-server.js';
import { startMediaServer } from './media-server.js';
import { processMessageMedia } from './services/file-upload.js';
import { FrpcManager } from './tunnel/frpc-manager.js';
import { DeviceAuth } from './tunnel/device-auth.js';
import { handleMessage as mockHandleMessage, abortConversation as mockAbortConversation } from './mock/mock-handler.js';
import { createMockActionHandler } from './mock/mock-action-handler.js';
import { handleReadFile } from './mock/mock-file-handler.js';
import { CronService } from './services/cron-service.js';
import { initLogger } from './logger.js';

const serverDir = path.join(__dirname, '..');

// 全局异常防御
process.on('uncaughtException', (err) => console.error('[Server] Uncaught exception:', err.message));
process.on('unhandledRejection', (reason) => console.error('[Server] Unhandled rejection:', reason));

/** 检查端口是否被占用，如果占用则立即退出 */
function checkPortConflict(port: number, label: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const net = require('net');
    const tester = net.createServer();
    tester.once('error', (err: NodeJS.ErrnoException) => {
      if (err.code === 'EADDRINUSE') {
        console.error(`[Server] ❌ Fatal: ${label} port ${port} is already in use.`);
        console.error(`[Server] Another Clawke Server instance may be running.`);
        console.error(`[Server] Use "lsof -i :${port}" to find the process, or "kill $(lsof -ti :${port})" to stop it.`);
        process.exit(1);
      }
      reject(err);
    });
    tester.once('listening', () => {
      tester.close(() => resolve());
    });
    tester.listen(port);
  });
}

async function main() {
  // 日志持久化：所有 console.log/error/warn 自动写入 ~/.clawke/logs/server-YYYY-MM-DD.log
  initLogger();

  const config = loadConfig();
  const MODE = config.server.mode;
  const HTTP_PORT = config.server.httpPort;
  const MEDIA_PORT = config.server.mediaPort;
  const UPSTREAM_PORT = config.server.upstreamPort;

  // 启动前检查端口冲突
  await checkPortConflict(HTTP_PORT, 'HTTP');

  console.log(`[Server] 🚀 Mode: ${MODE}`);

  // 确保运行时目录存在
  ensureDirectories();

  // ━━━ Relay（可选）━━━
  let frpcManager: InstanceType<typeof FrpcManager> | null = null;
  if (MODE !== 'mock') {
    await startRelay();
  } else {
    console.log('[Server] Relay skipped (mock mode)');
  }

  async function startRelay() {
    // 读取配置（从 ~/.clawke/clawke.json）
    const configPath = getConfigPath();
    const freshConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
    const relay = freshConfig.relay || {};

    if (relay.enable === false) {
      console.log('[Server] Relay disabled');
      return;
    }

    if (relay.token && relay.relayUrl && relay.serverAddr) {
      const relaySubdomain = new URL(relay.relayUrl).hostname.split('.')[0];
      frpcManager = new FrpcManager({
        relayToken: relay.token, relaySubdomain, httpPort: HTTP_PORT,
        relayServer: relay.serverAddr, relayPort: relay.serverPort,
      });
      frpcManager.start();
      return;
    }

    // Device Auth 流程
    console.log('[Server] ⚠️  No relay credentials found. Starting device authorization...');
    const auth = new DeviceAuth('https://clawke.ai');
    const onSigInt = () => { auth.cancel(); process.exit(0); };
    process.on('SIGINT', onSigInt);

    try {
      const credentials = await auth.authorize();
      process.removeListener('SIGINT', onSigInt);
      console.log(`[Server] ✅ Authorization successful! Relay: ${credentials.relayUrl}`);

      const cfg = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
      cfg.relay = {
        enable: true, serverAddr: credentials.serverAddr || 'relay.clawke.ai',
        serverPort: credentials.serverPort || 7000,
        token: credentials.token, relayUrl: credentials.relayUrl,
      };
      fs.writeFileSync(configPath, JSON.stringify(cfg, null, 2) + '\n');

      const sub = new URL(credentials.relayUrl).hostname.split('.')[0];
      frpcManager = new FrpcManager({
        relayToken: credentials.token, relaySubdomain: sub, httpPort: HTTP_PORT,
        relayServer: credentials.serverAddr || 'relay.clawke.ai',
        relayPort: credentials.serverPort || 7000,
      });
      frpcManager.start();
      console.log('[Server] 🌐 Server is online.');
    } catch (err) {
      console.error(`[Server] ❌ Device auth failed: ${(err as Error).message}`);
      process.exit(1);
    }
  }

  // ━━━ Store 层 ━━━
  const dbPath = process.env.NODE_TEST ? ':memory:' : path.join(DATA_DIR, 'clawke.db');
  const db = new Database(dbPath);
  const messageStore = new MessageStore(db);
  const configStore = new ConversationConfigStore(db);  // 必须先于 ConversationStore（后者引用 conversation_configs 表）
  const conversationStore = new ConversationStore(db);
  db.startCleanupScheduler();

  // ━━━ Protocol 层 ━━━
  const cupHandler = new CupV2Handler(messageStore, conversationStore);

  // ━━━ Service 层 ━━━
  const statsCollector = new StatsCollector(DATA_DIR);
  const configDir = path.join(serverDir, 'config');
  const versionChecker = new VersionChecker(configDir);
  versionChecker.startPeriodicCheck();
  statsCollector.startPeriodicSave();

  // ━━━ 通信层 ━━━
  const { server: unifiedServer, wss: clientWss } = startUnifiedServer(HTTP_PORT);
  const mediaServer = startMediaServer(MEDIA_PORT);

  // ━━━ Handler 层 ━━━
  const registry = new EventRegistry();
  const actionRouter = new ActionRouter();

  registry.register('sync', createSyncHandler(cupHandler, versionChecker));
  registry.register('check_update', createCheckUpdateHandler(versionChecker));
  registry.register('ping', createPingHandler({
    getConnectedAccountIds: () => [],   // 被 openclaw 模式覆盖
    agentName: MODE === 'mock' ? 'Mock Agent' : 'OpenClaw',
  }));
  registry.register('request_dashboard', createDashboardHandler({
    getDashboardJson: (c: number, ai: boolean, l: string) => statsCollector.getDashboardJson(c, ai, l),
    getClientCount: () => clientWss.clients.size,
    isUpstreamConnected: () => false,     // 被 openclaw 模式覆盖
  }));
  registry.register('user_action', createUserActionHandler(actionRouter));

  // ━━━ Mock / OpenClaw 分叉 ━━━
  if (MODE === 'mock') {
    statsCollector.populateMockData();

    // Mock handler + CronService
    const cronService = new CronService(db);
    const mockActionHandler = createMockActionHandler(cronService);

    registry.register('user_message', createUserMessageHandler({
      cupHandler,
      stats: statsCollector,
      mockHandler: {
        simulateResponse: async (ctx) => {
          const convId = ctx.payload.context?.account_id || 'default';
          await mockHandleMessage(ctx.ws as any, ctx.payload.data || {}, convId, cupHandler, config.server.fastMode || false);
        },
      },
      processMessageMedia,
    }));
    registry.register('abort', createAbortHandler({
      mockAbort: (convId: string) => mockAbortConversation(convId),
    }));
    registry.register('user_action', createUserActionHandler(actionRouter));
    registry.register('read_file', (ctx) => {
      handleReadFile(ctx.ws as any, ctx.payload);
    });

    // Mock 模式下客户端连接 → 通知 ai_connected
    clientWss.on('connection', (ws: unknown) => {
      sendToClient(ws, {
        payload_type: 'system_status',
        status: 'ai_connected',
        agent_name: 'Mock Agent',
      });
    });

    console.log(`[Server] Mock FAST_MODE=${config.server.fastMode || false}`);

  } else if (MODE === 'openclaw') {
    const { startOpenClawListener, sendToOpenClaw, isUpstreamConnected, getConnectedAccountIds, queryGatewayModels, queryGatewaySkills } =
      await import('./upstream/openclaw-listener.js');
    const { initConfigRoutes } = await import('./routes/config-routes.js');
    const { initConversationRoutes } = await import('./routes/conversation-routes.js');

    // 初始化配置路由（models/skills 查询路由到对应 Gateway）
    initConfigRoutes({
      configStore,
      queryModels: queryGatewayModels,
      querySkills: queryGatewaySkills,
    });

    // 初始化会话路由
    initConversationRoutes({ conversationStore });

    // MessageRouter — 上游消息 → 翻译 → 存储 → 统计 → 广播
    const messageRouter = new MessageRouter(
      translateToCup, cupHandler, statsCollector,
      (msg) => broadcastToClients(msg),
      conversationStore,
    );

    // 覆盖 ping handler 和 dashboard handler 的依赖
    registry.register('ping', createPingHandler({
      getConnectedAccountIds,
      agentName: 'OpenClaw',
    }));
    registry.register('request_dashboard', createDashboardHandler({
      getDashboardJson: (c: number, ai: boolean, l: string) => statsCollector.getDashboardJson(c, ai, l),
      getClientCount: () => clientWss.clients.size,
      isUpstreamConnected,
    }));

    registry.register('user_message', createUserMessageHandler({
      cupHandler,
      stats: statsCollector,
      forwardToUpstream: (accountId: string, upstreamMsg: unknown) => {
        // UpstreamMessage 标准协议直接发给 Gateway，不再翻译
        sendToOpenClaw(accountId, upstreamMsg as Record<string, unknown>);
      },
      broadcastToClients,
      messageRouter,
      processMessageMedia,
      configStore,
    }));
    registry.register('abort', createAbortHandler({
      forwardToUpstream: (accountId: string, msg: unknown) => {
        const m = msg as Record<string, unknown>;
        const conversationId = (m.conversation_id as string) || '';
        // 客户端已从 conversation 记录取正确的 accountId（如 "OpenClaw"），
        // 格式必须匹配 Gateway 的 InboundMessageType.Abort = "abort"
        sendToOpenClaw(accountId, { type: 'abort', conversation_id: conversationId });
      },
      messageRouter,
    }));

    // 上游消息处理 — 使用 MessageRouter
    const upstreamWss = startOpenClawListener(UPSTREAM_PORT, (payload: Record<string, unknown>) => {
      console.log('[Gateway] Upstream message:', JSON.stringify(payload).slice(0, 200));
      const accountId = (payload.account_id as string) || 'default';
      messageRouter.handleUpstreamMessage(payload as any, accountId);
    }, (accountId: string, agentName: string) => {
      // Gateway 连接时自动创建默认会话（如果该 account 还没有会话）
      const existing = conversationStore.listByAccount(accountId);
      if (existing.length === 0) {
        const crypto = require('crypto');
        const convId = crypto.randomUUID();
        conversationStore.create(convId, 'ai', accountId, accountId);
        console.log(`[Server] Auto-created default conversation for account=${accountId}: ${convId}`);
        broadcastToClients({ payload_type: 'conv_changed' });
      }
    });

    // 客户端连接 → 补发 ai_connected
    clientWss.on('connection', (ws: unknown) => {
      const accounts = getConnectedAccountIds();
      for (const accountId of accounts) {
        sendToClient(ws, {
          payload_type: 'system_status',
          status: 'ai_connected',
          agent_name: 'OpenClaw',
          account_id: accountId,
        });
      }
    });

    // 注册 EventRegistry 到 client-server（openclaw 模式）
    startClientServer(clientWss, (ws: unknown, payload: Record<string, unknown>) => {
      registry.dispatch(ws as any, payload as any);
    });

    console.log(`[Server] ✅ EventRegistry: ${registry.size} handlers registered`);

    // 优雅退出（openclaw 模式需要清理 upstream wss）
    const shutdownOC = () => {
      console.log('\n[Server] Shutting down...');
      if (frpcManager) frpcManager.stop();
      statsCollector.saveNow();
      statsCollector.stopPeriodicSave();
      versionChecker.stopPeriodicCheck();
      db.close();
      clientWss.clients.forEach((ws: { close: () => void }) => ws.close());
      upstreamWss.clients.forEach((ws: { close: () => void }) => ws.close());
      unifiedServer.close();
      mediaServer.close();
      upstreamWss.close(() => process.exit(0));
    };
    process.on('SIGINT', shutdownOC);
    process.on('SIGTERM', shutdownOC);
    return; // 不走通用 shutdown
  } else {
    console.error(`[Server] Unknown MODE: ${MODE}`);
    process.exit(1);
  }

  // ━━━ 启动 ━━━
  // 注册 EventRegistry 到 client-server
  startClientServer(clientWss, (ws: unknown, payload: Record<string, unknown>) => {
    registry.dispatch(ws as any, payload as any);
  });

  console.log(`[Server] ✅ EventRegistry: ${registry.size} handlers registered`);
  console.log(`[Server] ✅ ActionRouter: ${actionRouter.size} actions registered`);

  // 通用 Shutdown（mock 模式）
  const shutdown = () => {
    console.log('\n[Server] Shutting down...');
    if (frpcManager) frpcManager.stop();
    statsCollector.saveNow();
    statsCollector.stopPeriodicSave();
    versionChecker.stopPeriodicCheck();
    db.close();
    clientWss.clients.forEach((ws: { close: () => void }) => ws.close());
    unifiedServer.close();
    mediaServer.close(() => process.exit(0));
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch(err => {
  console.error('[Server] Fatal error:', err);
  process.exit(1);
});
