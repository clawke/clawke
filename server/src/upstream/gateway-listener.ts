/**
 * 上游 Gateway 监听器 — Upstream Gateway listener.
 *
 * 接收 OpenClaw / Hermes / Nanobot 等 Gateway WebSocket 连接，按 accountId 路由消息。
 * Accepts Gateway WebSocket connections and routes messages by accountId.
 */
import { WebSocketServer, WebSocket } from 'ws';
import { broadcastToClients, getClientConnections } from '../downstream/client-server.js';
import type { GatewayInfo } from '../types/gateways.js';

// accountId → WebSocket 路由表 — accountId to WebSocket routing table.
const upstreamConnections = new Map<string, WebSocket>();
const upstreamGatewayInfo = new Map<string, GatewayInfo>();
const activeStreamingIds = new Set<string>();
const TRANSIENT_GATEWAY_RESPONSE_TYPES = new Set([
  'models_response',
  'skills_response',
  'task_list_response',
  'task_get_response',
  'task_mutation_response',
  'task_run_response',
  'task_runs_response',
  'task_output_response',
  'skill_list_response',
  'skill_get_response',
  'skill_mutation_response',
  'skillhub_install_response',
  'gateway_system_response',
]);

export function isTransientGatewayResponseType(type: unknown): boolean {
  return typeof type === 'string' && TRANSIENT_GATEWAY_RESPONSE_TYPES.has(type);
}

export function toSkillHubInstallStatusPayload(payload: Record<string, unknown>): Record<string, unknown> {
  const { type: _type, install_id, request_id, ...rest } = payload;
  return {
    payload_type: 'skillhub_install_status',
    installId: String(install_id || request_id || ''),
    ...rest,
  };
}

export function startGatewayListener(
  port: number,
  messageHandler: (payload: Record<string, unknown>) => void,
  onGatewayIdentified?: (accountId: string, agentName: string) => void,
): WebSocketServer {
  const wss = new WebSocketServer({ port });
  console.log(`[Gateway] Upstream Gateway listener started, waiting on ws://127.0.0.1:${port}`);

  wss.on('connection', (ws: WebSocket) => {
    let accountId: string | null = null;

    ws.on('message', (raw: Buffer) => {
      let payload: Record<string, any>;
      try {
        payload = JSON.parse(raw.toString());
      } catch {
        console.error('[Gateway] Gateway JSON parse failed:', raw.toString());
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
        const displayName = typeof payload.agentName === 'string' && payload.agentName.trim()
          ? payload.agentName.trim()
          : 'OpenClaw';
        const gatewayType = typeof payload.gatewayType === 'string' && payload.gatewayType.trim()
          ? payload.gatewayType.trim()
          : 'openclaw';
        const capabilities = Array.isArray(payload.capabilities)
          ? payload.capabilities.map((item: unknown) => String(item)).filter(Boolean)
          : ['chat', 'tasks', 'skills', 'models'];
        const now = Date.now();

        upstreamGatewayInfo.set(accountId!, {
          gateway_id: accountId!,
          display_name: displayName,
          gateway_type: gatewayType,
          status: 'online',
          capabilities,
          clawke_home: stringValue(payload.clawkeHome) || stringValue(payload.clawke_home) || null,
          managed_skills_root: stringValue(payload.managedSkillsRoot) || stringValue(payload.managed_skills_root) || null,
          shared_skill_root: stringValue(payload.sharedSkillRoot) || stringValue(payload.shared_skill_root) || null,
          local_to_server: isLoopbackAddress(remote),
          last_connected_at: now,
          last_seen_at: now,
        });

        // 通知 server 层处理自动创建会话等逻辑 — Notify server layer for default conversation setup.
        if (onGatewayIdentified) {
          onGatewayIdentified(accountId!, displayName);
        }

        broadcastToClients({
          payload_type: 'system_status',
          status: 'ai_connected',
          agent_name: displayName,
          gateway_type: gatewayType,
          capabilities,
          account_id: accountId,
        });
        return;
      }

      if (accountId) {
        payload.account_id = payload.account_id || accountId;
      }

      if (payload.type === 'skillhub_install_status') {
        broadcastToClients(toSkillHubInstallStatusPayload(payload));
        return;
      }

      if (payload.type === 'e2e_disconnect_clients') {
        if (process.env.NODE_TEST === '1') {
          let closed = 0;
          for (const client of getClientConnections()) {
            if (client.readyState === 1) {
              client.close(1012, 'e2e_disconnect_clients');
              closed += 1;
            }
          }
          console.log(`[Gateway] UI E2E disconnected ${closed} client connection(s)`);
        }
        return;
      }

      // 临时响应由单次请求监听器处理，不走主路由 — Transient responses are handled by per-request listeners.
      if (isTransientGatewayResponseType(payload.type)) {
        return;
      }

      // 上行消息入口日志：记录 Gateway 发来的每条消息摘要 — Log each upstream message summary.
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
        upstreamGatewayInfo.delete(accountId);
        console.log(`[Gateway] Gateway disconnected: account=${accountId} (remaining: ${upstreamConnections.size})`);
        finalizeAllStreaming();
        broadcastToClients({
          payload_type: 'system_status',
          status: 'ai_disconnected',
          account_id: accountId,
        });
      }
    });

    ws.on('error', (err: Error) => console.error('[Gateway] Gateway WebSocket error:', err.message));
  });

  return wss;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

export function isLoopbackAddress(remoteAddress: string): boolean {
  return remoteAddress === '127.0.0.1'
    || remoteAddress === '::1'
    || remoteAddress === '::ffff:127.0.0.1';
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

/** 按 accountId 路由发送给对应的 Gateway upstream — Route outbound messages to the Gateway upstream by accountId. */
export function sendToGateway(accountId: string, jsonObj: Record<string, unknown>): void {
  const ws = upstreamConnections.get(accountId);
  if (ws && ws.readyState === 1) {
    try {
      if ((jsonObj as any).media) {
        console.log(`[Gateway] 📤 sendToGateway(${accountId}): media=${JSON.stringify((jsonObj as any).media)}`);
      }
      console.log(`[Gateway] ➡️  sendToGateway(${accountId}): type=${jsonObj.type}, text=${((jsonObj as any).text || '').slice(0, 50)}`);
      ws.send(JSON.stringify(jsonObj));
    } catch (err: any) {
      console.error(`[Gateway] ❌ sendToGateway(${accountId}) failed:`, err.message);
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

export function getUpstreamConnection(accountId: string): WebSocket | undefined {
  const ws = upstreamConnections.get(accountId);
  return ws && ws.readyState === 1 ? ws : undefined;
}

export function getConnectedAccountIds(): string[] {
  const ids: string[] = [];
  for (const [id, ws] of upstreamConnections) {
    if (ws.readyState === 1) ids.push(id);
  }
  return ids;
}

export function getConnectedGateways(): GatewayInfo[] {
  const gateways: GatewayInfo[] = [];
  for (const [id, ws] of upstreamConnections) {
    if (ws.readyState !== 1) continue;
    const info = upstreamGatewayInfo.get(id);
    gateways.push(info || {
      gateway_id: id,
      display_name: id,
      gateway_type: 'unknown',
      status: 'online',
      capabilities: ['chat'],
      last_connected_at: null,
      last_seen_at: Date.now(),
    });
  }
  return gateways;
}

export function trackStreamingId(msgId: string): void {
  activeStreamingIds.add(msgId);
}

export function untrackStreamingId(msgId: string): void {
  activeStreamingIds.delete(msgId);
}

/**
 * 通过 WS 查询指定 Gateway 的可用模型列表
 *
 * 发送 { type: "query_models" }，等待 { type: "models_response", models: [...] }
 * 超时 60 秒返回空数组。— Returns an empty array after a 60-second timeout.
 */
export type GatewayModelResponseItem = string | Record<string, unknown>;
export const GATEWAY_QUERY_TIMEOUT_MS = 60_000;

export function queryGatewayModels(accountId: string): Promise<GatewayModelResponseItem[]> {
  return _queryGateway<GatewayModelResponseItem[]>(accountId, 'query_models', 'models_response', 'models', []);
}

/**
 * 通过 WS 查询指定 Gateway 的可用 Skills 列表
 *
 * 发送 { type: "query_skills" }，等待 { type: "skills_response", skills: [...] }
 * 超时 60 秒返回空数组。— Returns an empty array after a 60-second timeout.
 */
export function queryGatewaySkills(accountId: string): Promise<Array<{ name: string; description: string }>> {
  return _queryGateway(accountId, 'query_skills', 'skills_response', 'skills', []);
}

/** 通用 Gateway WS 查询 */
function _queryGateway<T>(
  accountId: string,
  queryType: string,
  responseType: string,
  dataKey: string,
  fallback: T,
): Promise<T> {
  return new Promise((resolve) => {
    const ws = upstreamConnections.get(accountId);
    if (!ws || ws.readyState !== 1) {
      console.warn(`[Gateway] ${queryType}: no upstream for account=${accountId}`);
      resolve(fallback);
      return;
    }

    const timeout = setTimeout(() => {
      console.warn(`[Gateway] ${queryType}: timeout (${GATEWAY_QUERY_TIMEOUT_MS / 1000}s) for account=${accountId}`);
      cleanup();
      resolve(fallback);
    }, GATEWAY_QUERY_TIMEOUT_MS);

    const handler = (raw: Buffer) => {
      try {
        const msg = JSON.parse(raw.toString());
        if (msg.type === responseType) {
          cleanup();
          resolve(msg[dataKey] || fallback);
        }
      } catch { /* ignore non-JSON */ }
    };

    const cleanup = () => {
      clearTimeout(timeout);
      ws?.removeListener('message', handler);
    };

    ws.on('message', handler);
    ws.send(JSON.stringify({ type: queryType }));
  });
}
