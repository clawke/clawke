/**
 * OpenClaw 上游消息类型定义
 * 
 * Gateway 插件发送给 Clawke Server 的消息格式
 */

/** OpenClaw 消息类型 */
export type OpenClawMessageType =
  | 'agent_text_delta'
  | 'agent_text_done'
  | 'agent_text'
  | 'agent_media'
  | 'agent_tool_call'
  | 'agent_tool_result'
  | 'agent_thinking_delta'
  | 'agent_thinking_done'
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

  // text 相关
  delta?: string;
  fullText?: string;
  text?: string;

  // media 相关
  mediaUrl?: string;

  // tool 相关
  toolCallId?: string;
  toolName?: string;
  durationMs?: number;
  resultSummary?: string;
  error?: string;

  // usage 相关
  usage?: TokenUsage;
  model?: string;
  provider?: string;
}
