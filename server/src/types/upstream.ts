/**
 * Clawke 上游标准协议类型
 *
 * 定义 Clawke Server 与 Gateway 之间的通信标准。
 * 各 Gateway（OpenClaw、Nanobot 等）必须实现此协议。
 *
 * 上行（Client → AI）：UpstreamMessage
 * 下行（AI → Client）：UpstreamAgentMessage（即 agent_* 系列消息）
 */

// ────────────── 上行：Client → Gateway ──────────────

/** Clawke → Gateway 的标准消息 */
export interface UpstreamMessage {
  type: 'chat' | 'abort' | 'action';
  conversation_id: string;
  /** chat 消息文本（已从 CUP 格式解析，纯用户文本） */
  text?: string;
  /** 消息类型：text / image / file / mixed */
  content_type?: string;
  /** 客户端消息 ID（去重用） */
  client_msg_id?: string;
  /** abort 时要中断的消息 ID */
  message_id?: string;
  /** action_id（user_action 类型） */
  action_id?: string;
  action_data?: Record<string, unknown>;
  /** 媒体信息 */
  media?: UpstreamMediaInfo;
}

/** 媒体信息（统一格式，Gateway 根据需要选择使用路径或 URL） */
export interface UpstreamMediaInfo {
  /** 本地文件路径（Gateway 与 CS 同机时用） */
  paths?: string[];
  /** 文件 MIME 类型 */
  types?: string[];
  /** 文件名 */
  names?: string[];
  /** 相对 URL（Gateway 通过 HTTP 下载用） */
  relativeUrls?: string[];
  /** CS HTTP base（拼接 relativeUrls） */
  httpBase?: string;
}

// ────────────── 下行：Gateway → Clawke ──────────────
// 下行消息类型已在 types/openclaw.ts 中定义（agent_text_delta 等）
// 这些消息类型事实上就是 Clawke 的标准格式，与 OpenClaw 无关
// Gateway 负责将自己的私有格式翻译为这些标准类型

/**
 * 将 CUP ClientPayload 转换为上游标准消息
 *
 * 解析 CUP 消息类型（text/image/file/mixed），提取纯文本。
 * media 信息由调用方传入（已经过 processMessageMedia 处理）。
 */
export function toUpstreamMessage(
  payload: { data?: Record<string, unknown>; context?: Record<string, unknown>; action?: Record<string, unknown> },
  type: 'chat' | 'abort' | 'action' = 'chat',
  media?: UpstreamMediaInfo | null,
): UpstreamMessage {
  const data = payload.data || {};
  const context = payload.context || {};

  const msg: UpstreamMessage = {
    type,
    conversation_id: (context.account_id as string) || 'default',
  };

  if (type === 'chat') {
    const contentType = (data.type as string) || 'text';
    msg.content_type = contentType;
    msg.client_msg_id = context.client_msg_id as string | undefined;

    // 从 CUP 格式解析纯文本
    msg.text = extractTextFromCup(contentType, data);

    // 媒体信息
    if (media) {
      msg.media = media;
    }
  } else if (type === 'abort') {
    msg.message_id = data.message_id as string | undefined;
    msg.conversation_id = (context.account_id as string) || 'default';
  } else if (type === 'action') {
    const action = payload.action || {};
    msg.action_id = action.action_id as string | undefined;
    msg.action_data = action.data as Record<string, unknown> | undefined;
  }

  return msg;
}

/**
 * 从 CUP 消息格式提取纯文本
 *
 * 之前在 translateToOpenClaw 里做，现在提升为标准层
 */
function extractTextFromCup(contentType: string, data: Record<string, unknown>): string {
  switch (contentType) {
    case 'text':
      return (data.content as string) || '';
    case 'mixed': {
      try {
        const mixed = JSON.parse((data.content as string) || '{}');
        return mixed.text || '';
      } catch {
        return '';
      }
    }
    case 'image':
      return '[用户发送了一张图片]';
    case 'file': {
      try {
        const fileInfo = JSON.parse((data.content as string) || '{}');
        return `[用户发送了文件: ${fileInfo.name || 'unknown'}]`;
      } catch {
        return '[用户发送了一个文件]';
      }
    }
    default:
      return (data.content as string) || '';
  }
}
