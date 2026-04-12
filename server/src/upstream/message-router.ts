/**
 * MessageRouter — 上游消息路由器（副作用汇聚点）
 *
 * 接收上游 agent_* 消息 → 翻译为 CUP → 存储 → 统计 → 广播
 * 这是整个系统中唯一允许将翻译结果接入存储和统计的地方。
 */
import type { OpenClawMessage } from '../types/openclaw.js';
import type { TranslatedResult, CupEncodedMessage } from '../translator/cup-encoder.js';
import type { CupV2Handler } from '../protocol/cup-v2-handler.js';

/** 统计收集器接口（解耦具体实现） */
export interface StatsCollectorLike {
  recordTokens(input: number, output: number, cache: number): void;
  recordToolCall(name: string, durationMs: number): void;
  recordMessage(): void;
  recordConversation(): void;
}

/** 翻译函数签名 */
type TranslateFn = (msg: OpenClawMessage, accountId: string) => TranslatedResult | null;

/** 广播函数签名 */
type BroadcastFn = (msg: Record<string, unknown>) => void;

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
    const conversationId = msg.conversation_id || accountId;

    // 中止拦截（以 conversationId 为 key）
    if (this.abortedSessions.has(conversationId)) {
      if (msg.type === 'agent_text_done' || msg.type === ('agent_turn_done' as string)) {
        this.abortedSessions.delete(conversationId);
        console.log(`[MessageRouter] Cleared abort for conversation=${conversationId} (upstream done)`);
      } else {
        console.log(`[MessageRouter] Discarded message for aborted conversation=${conversationId}`);
      }
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
      this.stats.recordTokens(
        u.input_tokens || u.input || 0,
        u.output_tokens || u.output || 0,
        u.cache_read_input_tokens || u.cacheRead || 0,
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
