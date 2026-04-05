/**
 * user-message handler — 处理用户发送消息
 *
 * 唯一的 mock/openclaw 模式分叉点。
 */
import type { HandlerContext } from '../event-registry.js';
import type { CupV2Handler } from '../protocol/cup-v2-handler.js';
import type { StatsCollectorLike, MessageRouter } from '../upstream/message-router.js';
import type { UpstreamMessage } from '../types/upstream.js';
import { toUpstreamMessage } from '../types/upstream.js';

interface UserMessageDeps {
  cupHandler: CupV2Handler;
  stats: StatsCollectorLike;
  /** Mock 模式: (ctx) => simulate AI response */
  mockHandler?: { simulateResponse: (ctx: HandlerContext) => Promise<void> } | null;
  /** OpenClaw 模式: forward to upstream */
  forwardToUpstream?: (accountId: string, msg: UpstreamMessage) => void;
  /** 广播给所有客户端 */
  broadcastToClients?: (msg: Record<string, unknown>) => void;
  /** 消息路由器（清除 abort 标记） */
  messageRouter?: MessageRouter | null;
  /** 媒体处理 */
  processMessageMedia?: (data: Record<string, unknown>) => Promise<unknown>;
}

export function createUserMessageHandler(deps: UserMessageDeps) {
  const seenAccounts = new Set<string>();

  return async (ctx: HandlerContext) => {
    const { cupHandler, stats, mockHandler, forwardToUpstream, broadcastToClients, messageRouter, processMessageMedia } = deps;

    // 0. 附件处理
    const data = ctx.payload.data as Record<string, unknown> || {};
    let media: unknown = null;
    if (processMessageMedia) {
      media = await processMessageMedia(data);
    }

    // 统计
    stats.recordMessage();
    if (!seenAccounts.has(ctx.accountId)) {
      seenAccounts.add(ctx.accountId);
      stats.recordConversation();
    }

    // 清除 abort 标记
    messageRouter?.clearAbort(ctx.accountId);

    // 1. ACK
    const ack = cupHandler.handleUserMessage(ctx.payload);
    ctx.respond(ack);

    // 2. 模式分叉
    if (mockHandler) {
      // Mock: delivered ACK + simulate response
      ctx.respond(cupHandler.makeDeliveredAck(ctx.payload.id || null));
      await mockHandler.simulateResponse(ctx);
    } else if (forwardToUpstream) {
      // OpenClaw: echo + forward + delivered
      if (broadcastToClients) {
        broadcastToClients({
          payload_type: 'message_echo',
          message_id: ctx.payload.context?.client_msg_id || ctx.payload.id,
          account_id: ctx.accountId,
          sender_device_id: ctx.payload.context?.device_id || 'unknown',
          is_echo: true,
          data: ctx.payload.data,
          created_at: Date.now(),
        });
      }

      const upstreamMsg = toUpstreamMessage(
        ctx.payload as { data?: Record<string, unknown>; context?: Record<string, unknown> },
        'chat',
        media as import('../types/upstream.js').UpstreamMediaInfo | null,
      );
      forwardToUpstream(ctx.accountId, upstreamMsg);
      ctx.respond(cupHandler.makeDeliveredAck(ctx.payload.id || null));
    }

    // 3. 日志
    const msgType = data.type || 'text';
    const clientMsgId = ctx.payload.context?.client_msg_id || '';
    if (msgType === 'image') {
      console.log(`[Tunnel] 🖼️  Image message: msgId=${clientMsgId}`);
    } else if (msgType === 'file') {
      console.log(`[Tunnel] 📎 File message: msgId=${clientMsgId}`);
    } else {
      console.log(`[Tunnel] 💬 Text message: msgId=${clientMsgId}, type=${msgType}`);
    }
  };
}
