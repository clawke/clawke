/**
 * 上游 OpenClaw/Gateway 监听器
 *
 * 接收 Gateway WebSocket 连接，按 accountId 路由消息。
 */
import { WebSocketServer, WebSocket } from 'ws';
import { broadcastToClients } from '../downstream/client-server.js';

// accountId → WebSocket 路由表
const upstreamConnections = new Map<string, WebSocket>();
const activeStreamingIds = new Set<string>();

export function startOpenClawListener(
  port: number,
  messageHandler: (payload: Record<string, unknown>) => void,
  onGatewayIdentified?: (accountId: string, agentName: string) => void,
): WebSocketServer {
  const wss = new WebSocketServer({ port });
  console.log(`[Gateway] Upstream OpenClaw listener started, waiting on ws://127.0.0.1:${port}`);

  wss.on('connection', (ws: WebSocket) => {
    let accountId: string | null = null;

    ws.on('message', (raw: Buffer) => {
      let payload: Record<string, any>;
      try {
        payload = JSON.parse(raw.toString());
      } catch {
        console.error('[Gateway] OpenClaw JSON parse failed:', raw.toString());
        return;
      }

      if (payload.type === 'identify') {
        accountId = payload.accountId || 'default';
        const existing = upstreamConnections.get(accountId!);
        if (existing && existing.readyState === 1) {
          console.log(`[Gateway] Replacing existing upstream for account=${accountId}`);
          existing.close();
        }
        upstreamConnections.set(accountId!, ws);
        const remote = (ws as any)._socket?.remoteAddress || 'unknown';
        const remotePort = (ws as any)._socket?.remotePort || '?';
        console.log(`[Gateway] ✅ Gateway connected by account_id=${accountId} remote=${remote}:${remotePort} (total: ${upstreamConnections.size})`);

        // 通知 server 层处理自动创建会话等逻辑
        if (onGatewayIdentified) {
          onGatewayIdentified(accountId!, 'OpenClaw');
        }

        broadcastToClients({
          payload_type: 'system_status',
          status: 'ai_connected',
          agent_name: 'OpenClaw',
          account_id: accountId,
        });
        return;
      }

      if (accountId) {
        payload.account_id = payload.account_id || accountId;
      }

      // *_response 由 _queryGateway 的临时 listener 处理，不走主路由
      if (
        payload.type === 'models_response' ||
        payload.type === 'skills_response' ||
        payload.type === 'skills_detail_response' ||
        payload.type === 'skill_save_response' ||
        payload.type === 'skill_delete_response' ||
        payload.type === 'skill_toggle_response'
      ) {
        return;
      }

      // 上行消息入口日志：记录 Gateway 发来的每条消息摘要
      const pType = payload.type || '?';
      const pMsgId = (payload.message_id as string) || '';
      const pConvId = (payload.conversation_id as string) || '';
      const pText = ((payload.text || payload.delta || '') as string).slice(0, 60);
      console.log(`[Gateway] ⬆️  Upstream msg: type=${pType} msgId=${pMsgId} conv=${pConvId} account=${accountId}${pText ? ` text="${pText}"` : ''}`);

      messageHandler(payload);
    });

    ws.on('close', () => {
      if (!accountId) {
        console.log('[Gateway] Unidentified upstream connection closed');
        return;
      }
      if (upstreamConnections.get(accountId) === ws) {
        upstreamConnections.delete(accountId);
        console.log(`[Gateway] OpenClaw Gateway disconnected: account=${accountId} (remaining: ${upstreamConnections.size})`);
        finalizeAllStreaming();
        broadcastToClients({
          payload_type: 'system_status',
          status: 'ai_disconnected',
          account_id: accountId,
        });
      }
    });

    ws.on('error', (err: Error) => console.error('[Gateway] OpenClaw WebSocket error:', err.message));
  });

  return wss;
}

export function finalizeAllStreaming(): void {
  for (const msgId of activeStreamingIds) {
    broadcastToClients({ message_id: msgId, payload_type: 'text_done' });
  }
  activeStreamingIds.clear();
  broadcastToClients({
    payload_type: 'system_status',
    status: 'stream_interrupted',
    message: 'AI 后端断开，输出可能不完整',
  });
}

/** 按 accountId 路由发送给对应的 upstream */
export function sendToOpenClaw(accountId: string, jsonObj: Record<string, unknown>): void {
  const ws = upstreamConnections.get(accountId);
  if (ws && ws.readyState === 1) {
    try {
      if ((jsonObj as any).media) {
        console.log(`[Gateway] 📤 sendToOpenClaw(${accountId}): media=${JSON.stringify((jsonObj as any).media)}`);
      }
      console.log(`[Gateway] ➡️  sendToOpenClaw(${accountId}): type=${jsonObj.type}, text=${((jsonObj as any).text || '').slice(0, 50)}`);
      ws.send(JSON.stringify(jsonObj));
    } catch (err: any) {
      console.error(`[Gateway] ❌ sendToOpenClaw(${accountId}) failed:`, err.message);
    }
  } else {
    const state = ws ? `readyState=${ws.readyState}` : 'no ws';
    console.warn(`[Gateway] ⚠️  No upstream connection for account=${accountId} (${state})`);
  }
}

export function isUpstreamConnected(accountId?: string): boolean {
  if (accountId) {
    const ws = upstreamConnections.get(accountId);
    return ws !== null && ws !== undefined && ws.readyState === 1;
  }
  for (const ws of upstreamConnections.values()) {
    if (ws.readyState === 1) return true;
  }
  return false;
}

export function getConnectedAccountIds(): string[] {
  const ids: string[] = [];
  for (const [id, ws] of upstreamConnections) {
    if (ws.readyState === 1) ids.push(id);
  }
  return ids;
}

export function trackStreamingId(msgId: string): void {
  activeStreamingIds.add(msgId);
}

export function untrackStreamingId(msgId: string): void {
  activeStreamingIds.delete(msgId);
}

export interface GatewaySkillSummary {
  name: string;
  description: string;
  dir_name?: string;
  source?: string;
  disabled?: boolean;
}

export interface GatewaySkillDetail {
  ok: boolean;
  dir_name: string;
  content?: string;
  name?: string;
  description?: string;
  source?: string;
  disabled?: boolean;
  error?: string;
}

export interface GatewayMutationResponse {
  ok: boolean;
  error?: string;
}

/**
 * 通过 WS 查询指定 Gateway 的可用模型列表
 *
 * 发送 { type: "query_models" }，等待 { type: "models_response", models: [...] }
 * 超时 5 秒返回空数组。
 */
export function queryGatewayModels(accountId: string): Promise<string[]> {
  return _queryGateway<string[]>(
    accountId,
    { type: 'query_models' },
    'models_response',
    (msg) => (Array.isArray(msg.models) ? msg.models : []),
    [],
  );
}

/**
 * 通过 WS 查询指定 Gateway 的可用 Skills 列表
 *
 * 发送 { type: "query_skills" }，等待 { type: "skills_response", skills: [...] }
 * 超时 5 秒返回空数组。
 */
export function queryGatewaySkills(accountId: string): Promise<GatewaySkillSummary[]> {
  return _queryGateway<GatewaySkillSummary[]>(
    accountId,
    { type: 'query_skills' },
    'skills_response',
    (msg) => (Array.isArray(msg.skills) ? msg.skills : []),
    [],
  );
}

export function queryGatewaySkillDetail(accountId: string, dirName: string): Promise<GatewaySkillDetail> {
  return _queryGateway<GatewaySkillDetail>(
    accountId,
    { type: 'query_skills_detail', dir_name: dirName },
    'skills_detail_response',
    (msg) => ({
      ok: msg.ok === true,
      dir_name: String(msg.dir_name || dirName),
      content: typeof msg.content === 'string' ? msg.content : undefined,
      name: typeof msg.name === 'string' ? msg.name : undefined,
      description: typeof msg.description === 'string' ? msg.description : undefined,
      source: typeof msg.source === 'string' ? msg.source : undefined,
      disabled: msg.disabled === true,
      error: typeof msg.error === 'string' ? msg.error : undefined,
    }),
    { ok: false, dir_name: dirName, error: 'gateway unavailable' },
  );
}

export function sendGatewaySkillSave(
  accountId: string,
  dirName: string,
  content: string,
): Promise<GatewayMutationResponse> {
  return _queryGateway<GatewayMutationResponse>(
    accountId,
    { type: 'skill_save', dir_name: dirName, content },
    'skill_save_response',
    (msg) => ({ ok: msg.ok === true, error: typeof msg.error === 'string' ? msg.error : undefined }),
    { ok: false, error: 'gateway unavailable' },
  );
}

export function sendGatewaySkillDelete(accountId: string, dirName: string): Promise<GatewayMutationResponse> {
  return _queryGateway<GatewayMutationResponse>(
    accountId,
    { type: 'skill_delete', dir_name: dirName },
    'skill_delete_response',
    (msg) => ({ ok: msg.ok === true, error: typeof msg.error === 'string' ? msg.error : undefined }),
    { ok: false, error: 'gateway unavailable' },
  );
}

export function sendGatewaySkillToggle(
  accountId: string,
  dirName: string,
  disabled: boolean,
): Promise<GatewayMutationResponse> {
  return _queryGateway<GatewayMutationResponse>(
    accountId,
    { type: 'skill_toggle', dir_name: dirName, disabled },
    'skill_toggle_response',
    (msg) => ({ ok: msg.ok === true, error: typeof msg.error === 'string' ? msg.error : undefined }),
    { ok: false, error: 'gateway unavailable' },
  );
}

/** 通用 Gateway WS 查询 */
function _queryGateway<T>(
  accountId: string,
  request: Record<string, unknown>,
  responseType: string,
  parser: (msg: Record<string, any>) => T,
  fallback: T,
): Promise<T> {
  return new Promise((resolve) => {
    const ws = upstreamConnections.get(accountId);
    if (!ws || ws.readyState !== 1) {
      console.warn(`[Gateway] ${String(request.type)}: no upstream for account=${accountId}`);
      resolve(fallback);
      return;
    }

    const timeout = setTimeout(() => {
      console.warn(`[Gateway] ${String(request.type)}: timeout (5s) for account=${accountId}`);
      cleanup();
      resolve(fallback);
    }, 5000);

    const handler = (raw: Buffer) => {
      try {
        const msg = JSON.parse(raw.toString());
        if (msg.type === responseType) {
          cleanup();
          resolve(parser(msg));
        }
      } catch { /* ignore non-JSON */ }
    };

    const cleanup = () => {
      clearTimeout(timeout);
      ws?.removeListener('message', handler);
    };

    ws.on('message', handler);
    ws.send(JSON.stringify(request));
  });
}

