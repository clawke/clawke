/**
 * abort handler
 */
import type { HandlerContext } from '../event-registry.js';
import type { MessageRouter } from '../upstream/message-router.js';
import type { UpstreamMessage } from '../types/upstream.js';

interface AbortDeps {
  /** Mock 模式: abort 对话 */
  mockAbort?: (convId: string) => void;
  /** OpenClaw 模式: 通知上游 */
  forwardToUpstream?: (accountId: string, msg: UpstreamMessage) => void;
  /** 消息路由器（标记 abort） */
  messageRouter?: MessageRouter | null;
}

export function createAbortHandler(deps: AbortDeps) {
  return (ctx: HandlerContext) => {
    const accountId = (ctx.payload.data as Record<string, unknown>)?.account_id as string || ctx.accountId;

    if (deps.mockAbort) {
      // Mock 模式
      ctx.respond({
        payload_type: 'system_status',
        status: 'stream_interrupted',
        message: '用户已中止',
      });
      deps.mockAbort(accountId);
      console.log(`[Tunnel] Mock aborted conversation ${accountId}`);
    } else if (deps.forwardToUpstream) {
      // OpenClaw 模式
      deps.messageRouter?.abortSession(accountId);
      deps.forwardToUpstream(accountId, {
        type: 'abort',
        conversation_id: accountId,
        message_id: (ctx.payload.data as Record<string, unknown>)?.message_id as string,
      });
    }
  };
}
