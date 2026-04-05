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
        console.log(`[Gateway] OpenClaw Gateway identified: account=${accountId} remote=${remote}:${remotePort} (total: ${upstreamConnections.size})`);

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
      if ((jsonObj as any).mediaPaths || (jsonObj as any).mediaRelativeUrls) {
        console.log(`[Gateway] 📤 sendToOpenClaw(${accountId}): keys=${Object.keys(jsonObj).join(',')}, relUrls=${JSON.stringify((jsonObj as any).mediaRelativeUrls)}, paths=${JSON.stringify((jsonObj as any).mediaPaths)}`);
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
