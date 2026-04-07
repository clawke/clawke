/**
 * SDK stream-json → CUP 协议转译器
 *
 * 将 Claude Code 的 stdout JSON 消息转换为 CUP 协议消息，
 * 复用已有的 CUP payload_type 体系（text_delta / thinking_delta / ui_component 等）
 */
import type { SdkMessage } from './types.js';

export interface CupOutput {
  payload_type: string;
  message_id?: string;
  account_id?: string;
  [key: string]: unknown;
}

/**
 * 将单条 SDK 消息转换为一条或多条 CUP 消息
 */
export function translateSdkToCup(sdkMsg: SdkMessage, accountId: string = 'cli'): CupOutput[] {
  const cups: CupOutput[] = [];
  const msgId = sdkMsg.uuid || `cli_${Date.now()}`;

  switch (sdkMsg.type) {
    case 'system': {
      if (sdkMsg.subtype === 'init') {
        cups.push({
          payload_type: 'system_status',
          status: 'ai_connected',
          agent_name: 'Claude Code',
          account_id: accountId,
          session_id: sdkMsg.session_id,
        });
      }
      break;
    }

    case 'assistant': {
      const content = sdkMsg.message?.content || [];
      for (const block of content) {
        if (block.type === 'text' && block.text) {
          cups.push({
            payload_type: 'text_delta',
            message_id: msgId,
            account_id: accountId,
            content: block.text,
          });
        }
        if (block.type === 'thinking' && block.thinking) {
          cups.push({
            payload_type: 'thinking_delta',
            message_id: msgId,
            account_id: accountId,
            content: block.thinking,
          });
        }
        if (block.type === 'tool_use') {
          cups.push({
            payload_type: 'tool_call_start',
            message_id: `${msgId}_tool`,
            tool_call_id: block.id || `tool_${Date.now()}`,
            tool_name: block.name || 'tool',
            tool_input_summary: JSON.stringify(block.input || {}).slice(0, 200),
            account_id: accountId,
          });
        }
        if (block.type === 'tool_result') {
          cups.push({
            payload_type: 'tool_call_done',
            message_id: `${msgId}_tool_done`,
            tool_call_id: block.id || `tool_${Date.now()}`,
            tool_name: block.name || 'tool',
            status: 'completed',
            summary: (block.content || '').slice(0, 500),
            account_id: accountId,
          });
        }
      }
      break;
    }

    case 'result': {
      cups.push({
        payload_type: 'text_done',
        message_id: msgId,
        account_id: accountId,
      });

      // 附带 usage 信息
      if (sdkMsg.cost_usd || sdkMsg.duration_ms) {
        cups.push({
          payload_type: 'usage_report',
          message_id: msgId,
          account_id: accountId,
          usage: {
            cost_usd: sdkMsg.cost_usd,
            duration_ms: sdkMsg.duration_ms,
            duration_api_ms: sdkMsg.duration_api_ms,
            num_turns: sdkMsg.num_turns,
          },
        });
      }
      break;
    }

    case 'control_request': {
      const req = sdkMsg.request;
      if (req?.subtype === 'can_use_tool') {
        // 权限审批 → CUP ui_component（ActionConfirmation 卡片）
        cups.push({
          payload_type: 'ui_component',
          message_id: `perm_${sdkMsg.request_id}`,
          account_id: accountId,
          role: 'agent',
          agent_id: 'claude-code',
          component: {
            widget_name: 'ActionConfirmation',
            props: {
              request_id: sdkMsg.request_id,
              title: `Allow "${req.tool_name}"?`,
              tool_name: req.tool_name,
              input_summary: JSON.stringify(req.input || {}).slice(0, 300),
            },
            actions: [
              { action_id: 'cli_approve_tool', label: 'Allow', type: 'remote',
                data: { request_id: sdkMsg.request_id } },
              { action_id: 'cli_deny_tool', label: 'Deny', type: 'remote',
                data: { request_id: sdkMsg.request_id } },
            ],
          },
        });
      }
      break;
    }

    default:
      // 未知类型，忽略
      break;
  }

  return cups;
}
