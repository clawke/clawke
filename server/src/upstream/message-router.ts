/**
 * MessageRouter — 上游消息路由器（副作用汇聚点）
 *
 * 接收上游 agent_* 消息 → 翻译为 CUP → 存储 → 统计 → 广播
 * 这是整个系统中唯一允许将翻译结果接入存储和统计的地方。
 */
import type { OpenClawMessage } from '../types/openclaw.js';
import type { TranslatedResult, CupEncodedMessage } from '../translator/cup-encoder.js';
import type { CupV2Handler } from '../protocol/cup-v2-handler.js';
import type { ConversationStore } from '../store/conversation-store.js';
import { resolveGatewayAlertConversation } from '../services/gateway-alert-service.js';
import { buildPushAlert } from '../services/push-service.js';

/** 统计收集器接口（解耦具体实现） */
export interface StatsCollectorLike {
  recordTokens(
    input: number,
    output: number,
    cache: number,
    options?: {
      gatewayId?: string;
      conversationId?: string;
      model?: string;
      provider?: string;
      cacheWrite?: number;
      reasoning?: number;
    },
  ): void;
  recordToolCall(name: string, durationMs: number): void;
  recordMessage(): void;
  recordConversation(): void;
}

/** 翻译函数签名 */
type TranslateFn = (msg: OpenClawMessage, accountId: string) => TranslatedResult | null;

/** 广播函数签名 */
type BroadcastFn = (msg: Record<string, unknown>) => void;

export interface StoredAgentMessageNotification {
  conversationId: string;
  messageId: string;
  gatewayId: string;
  seq: number;
  title?: string;
  body?: string;
}

type StoredAgentMessageNotifier = (message: StoredAgentMessageNotification) => void | Promise<void>;

export class MessageRouter {
  /** 每个 conversation 最近的 text_done serverMsgId（agent_usage 关联用） */
  private lastTextDoneIds = new Map<string, string>();

  /** 已中止的会话（以 conversationId 为 key） */
  private abortedSessions = new Set<string>();

  constructor(
    private translateFn: TranslateFn,
    private cupHandler: CupV2Handler,
    private stats: StatsCollectorLike,
    private broadcast: BroadcastFn,
    private conversationStore?: ConversationStore,
    private notifyStoredAgentMessage?: StoredAgentMessageNotifier,
  ) {}

  /** 标记会话为已中止（以 conversationId 为 key） */
  abortSession(conversationId: string): void {
    this.abortedSessions.add(conversationId);
    console.log(`[MessageRouter] Conversation ${conversationId} aborted`);
  }

  /** 清除中止标记（新消息时调用） */
  clearAbort(conversationId: string): void {
    if (this.abortedSessions.has(conversationId)) {
      this.abortedSessions.delete(conversationId);
      console.log(`[MessageRouter] Cleared abort for conversation=${conversationId}`);
    }
  }

  /**
   * 处理上游消息
   */
  handleUpstreamMessage(msg: OpenClawMessage, accountId: string): void {
    const gatewayId = accountId;
    // 入口日志：记录原始上游消息摘要
    const textPreview = ((msg as any).text || (msg as any).delta || '').slice(0, 60);
    console.log(`[MessageRouter] ⬅️  Incoming: type=${msg.type} msgId=${msg.message_id || ''} conv=${msg.conversation_id || ''} gateway=${gatewayId}${textPreview ? ` text="${textPreview}"` : ''}`);

    let conversationId = msg.conversation_id || accountId;

    if (msg.type === 'gateway_alert' && this.conversationStore) {
      const alertGatewayId = msg.gateway_id || gatewayId;
      conversationId = resolveGatewayAlertConversation(
        this.conversationStore,
        alertGatewayId,
        msg.target_conversation_id,
      );
      msg.conversation_id = conversationId;
    }

    // 会话路由兜底：conversationId 不是已知会话时，回退到最近活跃的会话
    // 解决 sendText 路径传入 peer 标识符（如 "clawke_user"）导致消息成为 DB 孤儿的问题
    if (this.conversationStore) {
      const existing = this.conversationStore.get(conversationId);
      if (!existing) {
        const sameGatewayConvs = this.conversationStore.listByAccount(gatewayId);
        if (sameGatewayConvs.length > 0) {
          const fallback = sameGatewayConvs[0].id; // listByAccount() 按 updated_at DESC 排序
          console.log(`[MessageRouter] Unknown conversation="${conversationId}", gateway="${gatewayId}", re-routing to default="${fallback}"`);
          conversationId = fallback;
        } else {
          const fallback = this.conversationStore.create(gatewayId, 'ai', gatewayId, gatewayId).id;
          console.log(`[MessageRouter] Unknown conversation="${conversationId}", gateway="${gatewayId}", created default="${fallback}"`);
          conversationId = fallback;
        }
      }
    }

    // 中止拦截（以 conversationId 为 key）
    // abort 标记只由 user_message handler 中的 clearAbort() 清除，
    // 上游消息不清除标记 — 防止 Gateway 回复（如 /abort 确认）意外放行后续消息。
    if (this.abortedSessions.has(conversationId)) {
      console.log(`[MessageRouter] Discarded message for aborted conversation=${conversationId} type=${msg.type}`);
      return;
    }

    // agent_turn_stats 只统计，不转发
    if (msg.type === ('agent_turn_stats' as string)) {
      const tools = (msg as unknown as Record<string, unknown>).tools as string[] | undefined;
      if (tools) {
        for (const toolName of tools) {
          this.stats.recordToolCall(toolName, 0);
        }
      }
      return;
    }

    // 翻译
    const result = this.translateFn(msg, accountId);
    if (!result) {
      console.warn(`[MessageRouter] translateToCup returned null for type=${msg.type}, account=${accountId}`);
      return;
    }

    // 处理元数据（副作用在这里，不在翻译器里）
    const { cupMessages, metadata } = result;

    // 存储（text_done / media）
    if (metadata.needsStore) {
      const { fullText, type, upstreamMsgId } = metadata.needsStore;
      const { serverMsgId, seq, ts } = this.cupHandler.storeAgentMessage(
        accountId, conversationId, fullText, type, upstreamMsgId
      );
      console.log(`[MessageRouter] 💾 Stored: serverMsgId=${serverMsgId} seq=${seq} conv=${conversationId} type=${type} len=${fullText.length}`);
      if (this.notifyStoredAgentMessage) {
        const alert = buildPushAlert(gatewayId, fullText);
        Promise.resolve(this.notifyStoredAgentMessage({
          conversationId,
          messageId: serverMsgId,
          gatewayId,
          seq,
          title: alert.title,
          body: alert.body,
        })).catch((error) => {
          console.warn(`[Push] notify stored message failed: ${error instanceof Error ? error.message : String(error)}`);
        });
      }
      // 用实际 serverMsgId 和 seq 替换 cupMessages 中的占位
      for (const m of cupMessages) {
        if (m.payload_type === 'text_done' || m.payload_type === 'ui_component') {
          m.message_id = serverMsgId;
          m.seq = seq;
          m.created_at = ts;
        }
        if (m.payload_type === 'usage_report') {
          m.message_id = serverMsgId;
        }
      }
      // 记录最近的 text_done serverMsgId（agent_usage 关联用）
      this.lastTextDoneIds.set(conversationId, serverMsgId);
    }

    // 独立 agent_usage 关联到最近的 text_done
    if (msg.type === 'agent_usage' && cupMessages.length > 0) {
      const lastId = this.lastTextDoneIds.get(conversationId);
      if (lastId) {
        cupMessages[0].message_id = lastId;
      }
    }

    // 统计
    if (metadata.usage) {
      const u = metadata.usage as Record<string, number>;
      const rawMsg = msg as unknown as Record<string, unknown>;
      this.stats.recordTokens(
        u.input_tokens || u.input || 0,
        u.output_tokens || u.output || 0,
        u.cache_read_input_tokens || u.cacheRead || 0,
        {
          gatewayId,
          conversationId,
          model: rawMsg.model as string || '',
          provider: rawMsg.provider as string || '',
          cacheWrite: u.cache_write_input_tokens || u.cacheWrite || 0,
          reasoning: u.reasoning_tokens || u.reasoning || 0,
        },
      );
    }
    if (metadata.toolCall) {
      this.stats.recordToolCall(metadata.toolCall.name, metadata.toolCall.durationMs);
    }

    // 广播（conversation_id 已在方法开头解析）
    console.log(`[MessageRouter] ✅ Translated to ${cupMessages.length} CUP messages`);
    for (const m of cupMessages) {
      if (conversationId) m.conversation_id = conversationId;
      this.broadcast(m);
    }
  }
}
