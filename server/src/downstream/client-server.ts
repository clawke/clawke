/**
 * 客户端 WebSocket 连接管理
 */
import type { WebSocket, WebSocketServer } from 'ws';

const clientConnections = new Set<WebSocket>();

/** 注册客户端 WebSocket 事件处理逻辑 */
export function startClientServer(
  wss: WebSocketServer,
  messageHandler: (ws: WebSocket, payload: Record<string, unknown>) => void,
): WebSocketServer {
  console.log(`[Client] Client WebSocket handler registered on unified server`);

  wss.on('connection', (ws: WebSocket) => {
    console.log('[Client] ✅ Flutter Client connected');
    clientConnections.add(ws);

    ws.on('message', (raw: Buffer) => {
      let payload: Record<string, unknown>;
      try {
        payload = JSON.parse(raw.toString());
      } catch {
        console.error('[Client] Client JSON parse failed:', raw.toString());
        return;
      }
      messageHandler(ws, payload);
    });

    ws.on('close', () => {
      console.log('[Client] Flutter Client disconnected');
      clientConnections.delete(ws);
    });

    ws.on('error', (err: Error) =>
      console.error('[Client] Client WebSocket error:', err.message),
    );
  });

  return wss;
}

export function broadcastToClients(jsonObj: Record<string, unknown>): void {
  if (!jsonObj.created_at) jsonObj.created_at = Date.now();
  const data = JSON.stringify(jsonObj);
  for (const ws of clientConnections) {
    if (ws.readyState === 1) {
      try {
        ws.send(data);
      } catch (err: any) {
        console.error(`[Client] ❌ broadcastToClients send failed:`, err.message);
      }
    }
  }
}

export function sendToClient(ws: WebSocket | unknown, jsonObj: Record<string, unknown>): void {
  if (!jsonObj.created_at) jsonObj.created_at = Date.now();
  const w = ws as WebSocket;
  if (w.readyState === 1) {
    try {
      w.send(JSON.stringify(jsonObj));
    } catch (err: any) {
      console.error(`[Client] ❌ sendToClient failed:`, err.message);
    }
  }
}

export function getClientConnections(): Set<WebSocket> {
  return clientConnections;
}
