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
    const data = ctx.payload.data as Record<string, unknown> | undefined;
    const conversationId = (ctx.payload.context?.conversation_id as string)
      || (data?.account_id as string)
      || ctx.accountId;

    if (deps.mockAbort) {
      // Mock 模式
      ctx.respond({
        payload_type: 'system_status',
        status: 'stream_interrupted',
        message: '用户已中止',
      });
      deps.mockAbort(conversationId);
      console.log(`[Tunnel] Mock aborted conversation ${conversationId}`);
    } else if (deps.forwardToUpstream) {
      // OpenClaw 模式
      deps.messageRouter?.abortSession(conversationId);
      deps.forwardToUpstream(ctx.accountId, {
        type: 'abort',
        conversation_id: conversationId,
        message_id: data?.message_id as string,
      });
    }
  };
}
