/**
 * OpenClaw 上游消息类型定义
 * 
 * Gateway 插件发送给 Clawke Server 的消息格式
 * 
 * 权威定义位于 Gateway 侧: gateways/openclaw/clawke/src/protocol.ts
 * 此处保持同步以供 Server 端类型检查使用
 */

/** OpenClaw 消息类型 */
export type OpenClawMessageType =
  // 流式输出
  | 'agent_text_delta'
  | 'agent_text_done'
  | 'agent_text'
  // 媒体
  | 'agent_media'
  // 工具调用
  | 'agent_tool_call'
  | 'agent_tool_result'
  // 推理（Thinking）
  | 'agent_thinking_delta'
  | 'agent_thinking_done'
  // 状态与统计
  | 'agent_typing'
  | 'agent_status'
  | 'agent_turn_stats'
  // 用量
  | 'agent_usage';

/** Token 用量信息 */
export interface TokenUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  /** 部分模型使用简写字段 */
  input?: number;
  output?: number;
  cacheRead?: number;
  model?: string;
  provider?: string;
}

/** OpenClaw 上游消息 */
export interface OpenClawMessage {
  type: OpenClawMessageType;
  message_id?: string;
  /** 会话 ID（多会话隔离路由用） */
  conversation_id?: string;

  // text 相关
  delta?: string;
  fullText?: string;
  text?: string;

  // media 相关
  mediaUrl?: string;

  // tool 相关
  toolCallId?: string;
  toolName?: string;
  toolTitle?: string;
  durationMs?: number;
  resultSummary?: string;
  error?: string;

  // usage 相关
  usage?: TokenUsage;
  model?: string;
  provider?: string;

  // status 相关
  status?: string;
}
