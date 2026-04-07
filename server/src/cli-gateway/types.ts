/**
 * Claude Code SDK stream-json 消息类型定义
 */

/** SDK 输出消息（Claude Code stdout 逐行 JSON） */
export interface SdkMessage {
  type: 'system' | 'assistant' | 'user' | 'result' | 'control_request';
  subtype?: string;
  uuid?: string;
  session_id?: string;
  request_id?: string;
  message?: {
    role: string;
    content: SdkContentBlock[];
  };
  request?: {
    subtype: string;
    tool_name?: string;
    input?: Record<string, unknown>;
  };
  result?: string;
  cost_usd?: number;
  duration_ms?: number;
  duration_api_ms?: number;
  is_error?: boolean;
  num_turns?: number;
  [key: string]: unknown;
}

export interface SdkContentBlock {
  type: 'text' | 'thinking' | 'tool_use' | 'tool_result';
  text?: string;
  thinking?: string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  content?: string;
}

/** SDK 输入消息（写入 Claude Code stdin） */
export interface SdkUserInput {
  type: 'user';
  message: {
    role: 'user';
    content: string;
  };
}

export interface SdkControlResponse {
  type: 'control_response';
  response: {
    subtype: 'success';
    request_id: string;
    response: {
      behavior: 'allow' | 'deny';
    };
  };
}
