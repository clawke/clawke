/**
 * cup-encoder — 纯函数翻译器
 *
 * 输入：上游标准消息（agent_text_delta / agent_text_done / ...）
 * 输出：CUP 消息数组 + 元数据
 *
 * ❌ 不调 recordTokens()
 * ❌ 不调 storeAgentMessage()
 * ❌ 不调 trackStreamingId()
 * ✅ 只做格式转换，所有副作用交给调用方（MessageRouter）
 */
import type { OpenClawMessage, TokenUsage } from '../types/openclaw.js';

/** 翻译结果 */
export interface TranslatedResult {
  /** CUP 消息数组（可能包含 text_done + usage_report） */
  cupMessages: CupEncodedMessage[];
  /** 元数据：由调用方决定如何处理 */
  metadata: {
    /** Token 用量（调用方决定是否统计） */
    usage?: TokenUsage;
    /** 流式消息 ID（调用方决定是否追踪） */
    streamingId?: string;
    /** 是否需要存储（text_done / media 需要） */
    needsStore?: {
      fullText: string;
      type: string;
      upstreamMsgId: string;
    };
    /** 是否取消流式追踪 */
    untrackStreamingId?: string;
    /** 工具调用信息（调用方决定是否统计） */
    toolCall?: { name: string; durationMs: number };
  };
}

/** CUP 编码消息（内部中间格式） */
export interface CupEncodedMessage {
  message_id: string;
  account_id: string;
  payload_type: string;
  [key: string]: unknown;
}

/**
 * 将上游消息翻译为 CUP 协议消息
 *
 * 纯函数：相同输入 → 相同输出，无副作用
 */
export function translateToCup(
  msg: OpenClawMessage,
  accountId: string = 'default'
): TranslatedResult | null {
  const msgId = msg.message_id || `msg_${Date.now()}`;

  switch (msg.type) {
    case 'agent_text_delta': {
      const content = msg.delta || '';
      if (!content) return null;

      return {
        cupMessages: [{
          message_id: msgId,
          account_id: accountId,
          payload_type: 'text_delta',
          content,
        }],
        metadata: { streamingId: msgId },
      };
    }

    case 'agent_text_done': {
      const fullText = msg.fullText || '';
      const usage = msg.usage;

      const cupMessages: CupEncodedMessage[] = [{
        message_id: msgId,  // 调用方存储后替换为 serverMsgId
        account_id: accountId,
        payload_type: 'text_done',
        // seq 和 created_at 由调用方存储后填充
      }];

      // usage_report（只生成一次，修复原来的双重计算 bug）
      if (usage || msg.model) {
        cupMessages.push({
          message_id: msgId,
          account_id: accountId,
          payload_type: 'usage_report',
          usage: usage || null,
          model: (usage as Record<string, unknown>)?.model as string || msg.model || '',
          provider: (usage as Record<string, unknown>)?.provider as string || msg.provider || '',
        });
      }

      return {
        cupMessages,
        metadata: {
          untrackStreamingId: msgId,
          usage: usage,
          needsStore: { fullText, type: 'text', upstreamMsgId: msgId },
        },
      };
    }

    case 'agent_text': {
      const text = msg.text || '';
      const usage = msg.usage;

      const cupMessages: CupEncodedMessage[] = [
        {
          message_id: `msg_${Date.now()}`,
          account_id: accountId,
          payload_type: 'text_delta',
          content: text,
        },
        {
          message_id: `msg_${Date.now()}`,
          account_id: accountId,
          payload_type: 'text_done',
        },
      ];

      if (usage || msg.model) {
        cupMessages.push({
          message_id: `msg_${Date.now()}`,
          account_id: accountId,
          payload_type: 'usage_report',
          usage: usage || null,
          model: (usage as Record<string, unknown>)?.model as string || msg.model || '',
          provider: (usage as Record<string, unknown>)?.provider as string || msg.provider || '',
        });
      }

      return {
        cupMessages,
        metadata: {
          usage,
          needsStore: { fullText: text, type: 'text', upstreamMsgId: `msg_${Date.now()}` },
        },
      };
    }

    case 'agent_media': {
      return {
        cupMessages: [{
          message_id: msgId,
          account_id: accountId,
          payload_type: 'ui_component',
          role: 'agent',
          agent_id: 'openclaw',
          component: {
            widget_name: 'ImageView',
            props: { url: msg.mediaUrl },
            actions: [],
          },
        }],
        metadata: {
          needsStore: {
            fullText: msg.mediaUrl || '',
            type: 'image',
            upstreamMsgId: msgId,
          },
        },
      };
    }

    case 'agent_tool_call':
      return {
        cupMessages: [{
          message_id: `${msgId}_tool_call`,
          tool_call_id: msg.toolCallId || `${msgId}_tool`,
          tool_name: msg.toolName || 'tool',
          tool_input_summary: '',
          account_id: accountId,
          payload_type: 'tool_call_start',
        }],
        metadata: {},
      };

    case 'agent_tool_result':
      return {
        cupMessages: [{
          message_id: `${msgId}_tool_done`,
          tool_call_id: msg.toolCallId || `${msgId}_tool`,
          tool_name: msg.toolName || 'tool',
          status: msg.error ? 'error' : 'completed',
          duration_ms: msg.durationMs || 0,
          summary: msg.resultSummary || '',
          account_id: accountId,
          payload_type: 'tool_call_done',
        }],
        metadata: {
          toolCall: {
            name: msg.toolName || 'tool',
            durationMs: msg.durationMs || 0,
          },
        },
      };

    case 'agent_thinking_delta':
      return {
        cupMessages: [{
          message_id: msgId,
          account_id: accountId,
          payload_type: 'thinking_delta',
          content: msg.delta || '',
        }],
        metadata: { streamingId: msgId },
      };

    case 'agent_thinking_done':
      return {
        cupMessages: [{
          message_id: msgId,
          account_id: accountId,
          payload_type: 'thinking_done',
        }],
        metadata: { untrackStreamingId: msgId },
      };

    case 'agent_usage': {
      if (!msg.usage && !msg.model) return null;
      const u = msg.usage || {};
      return {
        cupMessages: [{
          message_id: msgId,  // 调用方可用 lastTextDoneMsgId 替换
          account_id: accountId,
          payload_type: 'usage_report',
          usage: msg.usage ? u : null,
          model: (u as Record<string, unknown>).model as string || msg.model || '',
          provider: (u as Record<string, unknown>).provider as string || msg.provider || '',
        }],
        metadata: {
          usage: msg.usage,
        },
      };
    }

    default:
      console.warn('[Gateway] Unknown upstream message type:', msg.type);
      return null;
  }
}
