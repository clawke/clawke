/**
 * CUP (Clawke UI Protocol) 类型定义
 * 
 * 客户端 → 服务端 的事件类型和消息结构
 * 服务端 → 客户端 的 CUP 消息类型
 */

// ────────────── 客户端 → 服务端 ──────────────

/** 客户端支持的事件类型 */
export type EventType =
  | 'user_message'
  | 'sync'
  | 'check_update'
  | 'abort'
  | 'user_action'
  | 'request_dashboard'
  | 'ping';

/** 客户端上报的完整 payload */
export interface ClientPayload {
  id?: string;
  event_type: EventType;
  data?: Record<string, unknown>;
  context?: {
    account_id?: string;
    conversation_id?: string;
    client_msg_id?: string;
    device_id?: string;
  };
  action?: {
    action_id: string;
    type: string;
    trigger?: string;
    data?: Record<string, unknown>;
  };
}

// ────────────── 服务端 → 客户端 ──────────────

/** CUP payload 类型 */
export type CupPayloadType =
  | 'text_delta'
  | 'text_done'
  | 'thinking_delta'
  | 'thinking_done'
  | 'ui_component'
  | 'usage_report'
  | 'tool_call_start'
  | 'tool_call_done'
  | 'ctrl'
  | 'sync_response'
  | 'update_info';

/** CUP 基础消息（所有类型共享的字段） */
export interface CupMessageBase {
  message_id: string;
  account_id: string;
  payload_type: CupPayloadType;
  seq?: number;
  created_at?: string;
}

/** 文本 delta 消息 */
export interface TextDeltaMessage extends CupMessageBase {
  payload_type: 'text_delta';
  content: string;
}

/** 文本完成消息 */
export interface TextDoneMessage extends CupMessageBase {
  payload_type: 'text_done';
  seq: number;
  created_at: string;
}

/** Thinking delta 消息 */
export interface ThinkingDeltaMessage extends CupMessageBase {
  payload_type: 'thinking_delta';
  content: string;
}

/** Thinking 完成消息 */
export interface ThinkingDoneMessage extends CupMessageBase {
  payload_type: 'thinking_done';
}

/** UI 组件消息 */
export interface UiComponentMessage extends CupMessageBase {
  payload_type: 'ui_component';
  role: string;
  agent_id: string;
  component: {
    widget_name: string;
    props: Record<string, unknown>;
    actions: Array<{
      action_id: string;
      label: string;
      type: string;
    }>;
  };
}

/** Usage 报告消息 */
export interface UsageReportMessage extends CupMessageBase {
  payload_type: 'usage_report';
  usage: Record<string, number> | null;
  model: string;
  provider: string;
}

/** 工具调用开始消息 */
export interface ToolCallStartMessage extends CupMessageBase {
  payload_type: 'tool_call_start';
  tool_call_id: string;
  tool_name: string;
  tool_input_summary: string;
}

/** 工具调用完成消息 */
export interface ToolCallDoneMessage extends CupMessageBase {
  payload_type: 'tool_call_done';
  tool_call_id: string;
  tool_name: string;
  status: 'completed' | 'error';
  duration_ms: number;
  summary: string;
}

/** 控制消息 */
export interface CtrlMessage extends CupMessageBase {
  payload_type: 'ctrl';
  ctrl_type: string;
  [key: string]: unknown;
}

/** CUP 消息联合类型 */
export type CupMessage =
  | TextDeltaMessage
  | TextDoneMessage
  | ThinkingDeltaMessage
  | ThinkingDoneMessage
  | UiComponentMessage
  | UsageReportMessage
  | ToolCallStartMessage
  | ToolCallDoneMessage
  | CtrlMessage;
