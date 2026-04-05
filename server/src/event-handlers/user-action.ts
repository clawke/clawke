/**
 * user-action handler + ActionRouter
 *
 * 精确匹配 action_id → handler，替代 string.includes()。
 */
import type { HandlerContext } from '../event-registry.js';
import type { ClientPayload } from '../types/cup.js';

export type ActionHandler = (payload: ClientPayload, ctx: HandlerContext) => Record<string, unknown> | null;

export class ActionRouter {
  private handlers = new Map<string, ActionHandler>();

  /** 注册 action 处理器 */
  register(actionId: string, handler: ActionHandler): void {
    this.handlers.set(actionId, handler);
  }

  /** 分发 action */
  dispatch(payload: ClientPayload, ctx: HandlerContext): Record<string, unknown> | null {
    const actionId = payload.action?.action_id || '';
    const handler = this.handlers.get(actionId);
    if (!handler) {
      console.warn(`[ActionRouter] Unknown action_id: ${actionId}`);
      return null;
    }
    return handler(payload, ctx);
  }

  get size(): number {
    return this.handlers.size;
  }
}

/** 创建 user_action handler（内部使用 ActionRouter） */
export function createUserActionHandler(actionRouter: ActionRouter) {
  return (ctx: HandlerContext) => {
    console.log(`[Tunnel] ✅ Received user_action: action_id=${ctx.payload.action?.action_id || '-'}`);
    const result = actionRouter.dispatch(ctx.payload, ctx);
    if (result) {
      ctx.respond(result);
    }
  };
}
