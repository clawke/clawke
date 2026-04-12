/**
 * Mock 消息处理器
 *
 * 模拟 AI 流式回复（thinking + text delta + text done）
 */
import path from 'path';
import { sendToClient } from '../downstream/client-server.js';
import type { WebSocket } from 'ws';
import type { CupV2Handler } from '../protocol/cup-v2-handler.js';

// 动态加载 scenarios（仅在 mock 模式下需要，延迟加载避免缺失时崩溃）
const serverDir = path.join(__dirname, '..', '..');
let _matchScenario: ((text: string) => any) | null = null;
function getMatchScenario(): (text: string) => any {
  if (!_matchScenario) {
    try {
      _matchScenario = require(path.join(serverDir, 'mock', 'scenarios')).matchScenario;
    } catch {
      _matchScenario = (text: string) => ({ text: `Mock mode unavailable: ${text}`, thinking: null, component: null });
      console.warn('[Mock] mock/scenarios not found — mock replies will be placeholder text');
    }
  }
  return _matchScenario!;
}

const delay = (ms: number) => new Promise(res => setTimeout(res, ms));
const abortSignals = new Set<string>();

export function abortConversation(convId: string): void {
  abortSignals.add(convId);
}

export async function handleMessage(
  ws: WebSocket,
  payload: Record<string, any>,
  convId: string,
  cupHandler: CupV2Handler,
  fastMode: boolean,
): Promise<void> {
  const scenario = getMatchScenario()(payload.content || '');
  const text = scenario.text;
  const msgId = `msg_${Date.now()}`;
  const thinkingId = `think_${Date.now()}`;

  console.log(`[Tunnel] Message received: "${payload.content}", matched scenario, msgId=${msgId}`);

  // Thinking
  const thinkingText = scenario.thinking || `让我分析一下这个问题...\n\n用户说："${payload.content || ''}"，我需要理解他的意图并给出合适的回复。`;
  const thinkingDelay = scenario.thinking ? 30 : 5;
  let aborted = false;

  for (const char of thinkingText) {
    if ((ws as any).readyState !== 1 || abortSignals.has(convId)) { aborted = true; break; }
    sendToClient(ws, { message_id: thinkingId, account_id: convId, payload_type: 'thinking_delta', content: char });
    if (!fastMode) await delay(thinkingDelay);
  }
  sendToClient(ws, { message_id: thinkingId, account_id: convId, payload_type: 'thinking_done' });

  // Text delta
  let textOutput = '';
  if (!aborted) {
    for (const char of text) {
      if ((ws as any).readyState !== 1 || abortSignals.has(convId)) { aborted = true; break; }
      sendToClient(ws, { message_id: msgId, account_id: convId, payload_type: 'text_delta', content: char });
      textOutput += char;
      if (!fastMode) await delay(5);
    }
  }

  // Text done
  const finalText = aborted ? textOutput : text;
  const { serverMsgId, seq, ts } = cupHandler.storeAgentMessage(convId, convId, finalText, 'text', msgId);
  const doneMsg = { message_id: serverMsgId, account_id: convId, payload_type: 'text_done', seq, created_at: ts };
  console.log(`[Tunnel] ⬇️ Sent text_done${aborted ? ' (Aborted)' : ''}:`, JSON.stringify(doneMsg));
  sendToClient(ws, doneMsg);

  // UI component
  if (scenario.component && !aborted) {
    const { serverMsgId: compMsgId, seq: compSeq, ts: compTs } = cupHandler.storeAgentMessage(convId, convId, JSON.stringify(scenario.component), 'cup_component');
    sendToClient(ws, {
      role: 'agent', agent_id: 'mock_agent', message_id: compMsgId,
      account_id: convId, payload_type: 'ui_component', seq: compSeq, created_at: compTs,
      component: scenario.component,
    });
  }

  abortSignals.delete(convId);
}
