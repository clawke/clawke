/**
 * Clawke Server 入口 — 依赖组装 + 启动
 *
 * 职责：创建实例 → 组装依赖 → 启动 server → 注册信号处理
 * 规则：只做 new + 传参 + start，不含业务逻辑
 */
import * as path from 'path';
import * as fs from 'fs';
import { loadConfig, getConfigPath } from './config.js';
import { ensureDirectories, DATA_DIR } from './store/clawke-home.js';
import { Database } from './store/database.js';
import { MessageStore } from './store/message-store.js';
import { ConversationStore } from './store/conversation-store.js';
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

const serverDir = path.join(__dirname, '..');

// 全局异常防御
process.on('uncaughtException', (err) => console.error('[Server] Uncaught exception:', err.message));
process.on('unhandledRejection', (reason) => console.error('[Server] Unhandled rejection:', reason));

async function main() {
  const config = loadConfig();
  const MODE = config.server.mode;
  const HTTP_PORT = config.server.httpPort;
  const MEDIA_PORT = config.server.mediaPort;
  const UPSTREAM_PORT = config.server.upstreamPort;

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
    const { startOpenClawListener, sendToOpenClaw, isUpstreamConnected, getConnectedAccountIds } =
      await import('./upstream/openclaw-listener.js');

    // MessageRouter — 上游消息 → 翻译 → 存储 → 统计 → 广播
    const messageRouter = new MessageRouter(
      translateToCup, cupHandler, statsCollector,
      (msg) => broadcastToClients(msg),
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
    }));
    registry.register('abort', createAbortHandler({
      forwardToUpstream: (accountId: string, _msg: unknown) => {
        sendToOpenClaw(accountId, { action: 'chat.abort', sessionKey: accountId });
      },
      messageRouter,
    }));

    // 上游消息处理 — 使用 MessageRouter
    const upstreamWss = startOpenClawListener(UPSTREAM_PORT, (payload: Record<string, unknown>) => {
      console.log('[Gateway] Upstream message:', JSON.stringify(payload).slice(0, 200));
      const accountId = (payload.account_id as string) || 'default';
      messageRouter.handleUpstreamMessage(payload as any, accountId);
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
  } else if (MODE === 'cli') {
    // ━━━ CLI Gateway 模式：spawn Claude Code 子进程 ━━━
    const { CliGateway } = await import('./cli-gateway/cli-gateway.js');

    const cliCwd = process.env.CLI_CWD || process.cwd();
    const cliSessionId = process.env.CLI_SESSION_ID || undefined;
    const cliPermMode = process.env.CLI_PERMISSION_MODE || 'default';

    const gateway = new CliGateway({
      broadcast: (msg) => broadcastToClients(msg),
    });

    await gateway.start({
      cwd: cliCwd,
      sessionId: cliSessionId,
      permissionMode: cliPermMode,
    });

    // 覆盖 ping / dashboard handler
    registry.register('ping', createPingHandler({
      getConnectedAccountIds: () => gateway.running ? ['cli'] : [],
      agentName: 'Claude Code',
    }));
    registry.register('request_dashboard', createDashboardHandler({
      getDashboardJson: (c: number, ai: boolean, l: string) => statsCollector.getDashboardJson(c, ai, l),
      getClientCount: () => clientWss.clients.size,
      isUpstreamConnected: () => gateway.running,
    }));

    // 用户消息 → 转发给 Claude Code
    registry.register('user_message', (ctx) => {
      const data = ctx.payload.data as Record<string, unknown> || {};
      const text = (data.text as string) || (data.content as string) || '';
      if (!text) {
        console.warn('[CLI] Empty user message, ignoring');
        return;
      }

      statsCollector.recordMessage();

      // ACK
      const ack = cupHandler.handleUserMessage(ctx.payload);
      ctx.respond(ack);
      ctx.respond(cupHandler.makeDeliveredAck(ctx.payload.id || null));

      // Forward to Claude Code
      gateway.handleUserMessage(text);
    });

    // 中止
    registry.register('abort', (ctx) => {
      gateway.handleAbort();
    });

    // 权限审批 — 通过 ActionRouter
    actionRouter.register('cli_approve_tool', (payload) => {
      const requestId = payload.action?.data?.request_id as string;
      if (requestId) gateway.handleToolApproval(requestId, true);
      return null;
    });
    actionRouter.register('cli_deny_tool', (payload) => {
      const requestId = payload.action?.data?.request_id as string;
      if (requestId) gateway.handleToolApproval(requestId, false);
      return null;
    });

    // 客户端连接 → 补发状态
    clientWss.on('connection', (ws: unknown) => {
      if (gateway.running) {
        sendToClient(ws, {
          payload_type: 'system_status',
          status: 'ai_connected',
          agent_name: 'Claude Code',
          account_id: 'cli',
          session_id: gateway.sessionId,
        });
      }
    });

    // 注册 EventRegistry
    startClientServer(clientWss, (ws: unknown, payload: Record<string, unknown>) => {
      registry.dispatch(ws as any, payload as any);
    });

    console.log(`[Server] ✅ CLI Gateway mode — cwd: ${cliCwd}`);
    console.log(`[Server] ✅ EventRegistry: ${registry.size} handlers registered`);

    // 优雅退出
    const shutdownCli = () => {
      console.log('\n[Server] Shutting down CLI Gateway...');
      gateway.stop();
      if (frpcManager) frpcManager.stop();
      statsCollector.saveNow();
      statsCollector.stopPeriodicSave();
      versionChecker.stopPeriodicCheck();
      db.close();
      clientWss.clients.forEach((ws: { close: () => void }) => ws.close());
      unifiedServer.close();
      mediaServer.close(() => process.exit(0));
    };
    process.on('SIGINT', shutdownCli);
    process.on('SIGTERM', shutdownCli);
    return;
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
