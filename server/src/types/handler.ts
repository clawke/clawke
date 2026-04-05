/**
 * Handler 层类型定义
 */
import type WebSocket from 'ws';
import type { ClientPayload } from './cup';

/** 事件处理器的上下文 */
export interface HandlerContext {
  /** 客户端 WebSocket 连接 */
  ws: WebSocket;
  /** 账户 ID（路由标识） */
  accountId: string;
  /** 客户端发来的完整 payload */
  payload: ClientPayload;
}

/** 事件处理器函数签名 */
export type EventHandler = (ctx: HandlerContext) => Promise<void> | void;

/** Action 处理器的返回值 */
export interface ActionResult {
  /** 响应消息（发送给客户端） */
  response?: unknown;
  /** Toast 提示 */
  toast?: string;
}

/** Action 处理器函数签名 */
export type ActionHandler = (payload: ClientPayload) => ActionResult | null;

/** 消息存储结果 */
export interface StoreResult {
  serverMsgId: string;
  seq: number;
  ts: string;
}
