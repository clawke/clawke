/**
 * EventRegistry — 事件分发器
 *
 * 基于 Map<event_type, handler> 精确路由，替代 switch/case。
 */
import type WebSocket from 'ws';
import type { ClientPayload, EventType } from './types/cup.js';

/** Handler 上下文 */
export interface HandlerContext {
  ws: WebSocket;
  accountId: string;
  payload: ClientPayload;
  /** 回复当前客户端 */
  respond: (msg: Record<string, unknown>) => void;
}

export type EventHandler = (ctx: HandlerContext) => Promise<void> | void;

export class EventRegistry {
  private handlers = new Map<string, EventHandler>();

  /** 注册事件处理器 */
  register(eventType: string, handler: EventHandler): void {
    if (this.handlers.has(eventType)) {
      console.warn(`[EventRegistry] Overwriting handler for event_type: ${eventType}`);
    }
    this.handlers.set(eventType, handler);
  }

  /** 分发事件 */
  async dispatch(ws: WebSocket, payload: ClientPayload): Promise<void> {
    const eventType = payload.event_type;
    if (!eventType) {
      console.warn('[EventRegistry] Missing event_type in payload');
      return;
    }

    const handler = this.handlers.get(eventType);
    if (!handler) {
      console.warn(`[EventRegistry] Unknown event_type: ${eventType}`);
      return;
    }

    const accountId = payload.context?.account_id || 'default';
    const ctx: HandlerContext = {
      ws,
      accountId,
      payload,
      respond: (msg) => {
        if (!msg.created_at) msg.created_at = Date.now();
        if (ws.readyState === 1) {
          try { ws.send(JSON.stringify(msg)); }
          catch (err) { console.error('[EventRegistry] Send failed:', (err as Error).message); }
        }
      },
    };

    console.log(`[Tunnel] 📥 event_type=${eventType}, account=${accountId}, id=${payload.id || '-'}`);

    try {
      await handler(ctx);
    } catch (err) {
      console.error(`[EventRegistry] Handler error for ${eventType}:`, err);
    }
  }

  /** 已注册的事件数量（测试用） */
  get size(): number {
    return this.handlers.size;
  }
}
