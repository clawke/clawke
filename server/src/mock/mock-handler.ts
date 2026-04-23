/**
 * Mock 消息处理器
 *
 * 模拟 AI 流式回复（thinking + text delta + text done）
 * 特殊触发词：
 *   - "test approval" → 模拟审批请求卡片
 *   - "test clarify"  → 模拟澄清请求卡片
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

// ── 审批/澄清 等待队列 ──
const pendingApprovals = new Map<string, (choice: string) => void>();
const pendingClarifies = new Map<string, (response: string) => void>();

export function abortConversation(convId: string): void {
  abortSignals.add(convId);
}

/** Mock 模式下处理 approval_response（从 event-handlers 路由过来） */
export function handleMockApprovalResponse(convId: string, choice: string): void {
  const resolve = pendingApprovals.get(convId);
  if (resolve) {
    pendingApprovals.delete(convId);
    resolve(choice);
  }
}

/** Mock 模式下处理 clarify_response（从 event-handlers 路由过来） */
export function handleMockClarifyResponse(convId: string, response: string): void {
  const resolve = pendingClarifies.get(convId);
  if (resolve) {
    pendingClarifies.delete(convId);
    resolve(response);
  }
}

export async function handleMessage(
  ws: WebSocket,
  payload: Record<string, any>,
  convId: string,
  cupHandler: CupV2Handler,
  fastMode: boolean,
): Promise<void> {
  const content = (payload.content || '').trim().toLowerCase();

  // ── 特殊场景：test approval ──
  if (content === 'test approval') {
    return handleMockApproval(ws, convId, cupHandler, fastMode);
  }

  // ── 特殊场景：test clarify ──
  if (content === 'test clarify') {
    return handleMockClarify(ws, convId, cupHandler, fastMode);
  }

  // ── 特殊场景：test inline approval（模拟 OpenClaw 内联审批卡片）──
  if (content === 'test inline approval') {
    return handleMockInlineApproval(ws, convId, cupHandler, fastMode);
  }

  // ── 特殊场景：test inline clarify（模拟 OpenClaw 内联澄清卡片）──
  if (content === 'test inline clarify') {
    return handleMockInlineClarify(ws, convId, cupHandler, fastMode);
  }

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

// ── Mock Approval 场景 ──
async function handleMockApproval(
  ws: WebSocket, convId: string, cupHandler: CupV2Handler, fastMode: boolean,
): Promise<void> {
  const msgId = `msg_${Date.now()}`;

  // 1. 先流式输出一段说明文字
  const introText = '我需要执行一个危险操作，请确认：';
  for (const char of introText) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: msgId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const { serverMsgId, seq, ts } = cupHandler.storeAgentMessage(convId, convId, introText, 'text', msgId);
  sendToClient(ws, { message_id: serverMsgId, account_id: convId, payload_type: 'text_done', seq, created_at: ts });

  // 2. 发送 approval_request
  sendToClient(ws, {
    message_id: `approval_${Date.now()}`,
    account_id: convId,
    payload_type: 'approval_request',
    command: 'rm -rf /tmp/test_data',
    description: '删除临时测试数据目录（Mock 测试）',
    pattern_keys: [],
    conversation_id: convId,
  });
  console.log(`[Mock] 🔐 Sent approval_request to conv=${convId}`);

  // 3. 等待用户响应（最长 60s）
  const choice = await new Promise<string>((resolve) => {
    pendingApprovals.set(convId, resolve);
    setTimeout(() => {
      if (pendingApprovals.has(convId)) {
        pendingApprovals.delete(convId);
        resolve('timeout');
      }
    }, 60000);
  });
  console.log(`[Mock] 🔐 Got approval_response: choice=${choice}`);

  // 4. 根据结果回复
  const replyId = `msg_${Date.now()}`;
  const replyText = choice === 'deny'
    ? '好的，已取消操作。不会执行 `rm -rf /tmp/test_data`。'
    : choice === 'timeout'
    ? '⚠️ 审批超时，操作已取消。'
    : `✅ 已收到确认（${choice}），正在执行 \`rm -rf /tmp/test_data\`...\n\n执行完成！（Mock 模拟，未实际执行）`;

  for (const char of replyText) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: replyId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const r = cupHandler.storeAgentMessage(convId, convId, replyText, 'text', replyId);
  sendToClient(ws, { message_id: r.serverMsgId, account_id: convId, payload_type: 'text_done', seq: r.seq, created_at: r.ts });
}

// ── Mock Clarify 场景 ──
async function handleMockClarify(
  ws: WebSocket, convId: string, cupHandler: CupV2Handler, fastMode: boolean,
): Promise<void> {
  const msgId = `msg_${Date.now()}`;

  // 1. 先流式输出一段说明文字
  const introText = '我需要更多信息才能继续：';
  for (const char of introText) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: msgId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const { serverMsgId, seq, ts } = cupHandler.storeAgentMessage(convId, convId, introText, 'text', msgId);
  sendToClient(ws, { message_id: serverMsgId, account_id: convId, payload_type: 'text_done', seq, created_at: ts });

  // 2. 发送 clarify_request
  sendToClient(ws, {
    message_id: `clarify_${Date.now()}`,
    account_id: convId,
    payload_type: 'clarify_request',
    question: '你希望使用哪种编程语言？',
    choices: ['Python', 'TypeScript', 'Rust', 'Go'],
    conversation_id: convId,
  });
  console.log(`[Mock] ❓ Sent clarify_request to conv=${convId}`);

  // 3. 等待用户响应（最长 120s）
  const response = await new Promise<string>((resolve) => {
    pendingClarifies.set(convId, resolve);
    setTimeout(() => {
      if (pendingClarifies.has(convId)) {
        pendingClarifies.delete(convId);
        resolve('__timeout__');
      }
    }, 120000);
  });
  console.log(`[Mock] ❓ Got clarify_response: response="${response}"`);

  // 4. 根据结果回复
  const replyId = `msg_${Date.now()}`;
  const replyText = response === '__timeout__'
    ? '⚠️ 等待超时，请重新发送。'
    : `好的，你选择了 **${response}**！让我用 ${response} 来编写代码...\n\n\`\`\`${response.toLowerCase()}\n// Hello from ${response}!\nprint("Mock test complete")\n\`\`\`\n\n完成！（Mock 模拟）`;

  for (const char of replyText) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: replyId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const r = cupHandler.storeAgentMessage(convId, convId, replyText, 'text', replyId);
  sendToClient(ws, { message_id: r.serverMsgId, account_id: convId, payload_type: 'text_done', seq: r.seq, created_at: r.ts });
}

// ── Mock Inline Approval（OpenClaw 风格，代码块内嵌在消息中）──
async function handleMockInlineApproval(
  ws: WebSocket, convId: string, cupHandler: CupV2Handler, fastMode: boolean,
): Promise<void> {
  const msgId = `msg_${Date.now()}`;

  // 模拟 AI 回复中包含 approval 代码块（OpenClaw 风格）
  const text = `我分析了你的请求，需要执行以下操作。请确认：

\`\`\`approval
command: pkill -9 -f "Code Helper"
description: force kill processes
risk: high
\`\`\`

确认后我会继续执行。`;

  for (const char of text) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: msgId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const { serverMsgId, seq, ts } = cupHandler.storeAgentMessage(convId, convId, text, 'text', msgId);
  sendToClient(ws, { message_id: serverMsgId, account_id: convId, payload_type: 'text_done', seq, created_at: ts });
}

// ── Mock Inline Clarify（OpenClaw 风格，代码块内嵌在消息中）──
async function handleMockInlineClarify(
  ws: WebSocket, convId: string, cupHandler: CupV2Handler, fastMode: boolean,
): Promise<void> {
  const msgId = `msg_${Date.now()}`;

  // 模拟 AI 回复中包含 clarify 代码块（OpenClaw 风格）
  const text = `在开始之前，我需要确认一些信息：

\`\`\`clarify
question: 你希望使用哪种编程语言？
choices:
- Python
- TypeScript
- Rust
- Go
\`\`\`

请选择一个选项，或者直接输入其他答案。`;

  for (const char of text) {
    if ((ws as any).readyState !== 1) return;
    sendToClient(ws, { message_id: msgId, account_id: convId, payload_type: 'text_delta', content: char });
    if (!fastMode) await delay(5);
  }
  const { serverMsgId, seq, ts } = cupHandler.storeAgentMessage(convId, convId, text, 'text', msgId);
  sendToClient(ws, { message_id: serverMsgId, account_id: convId, payload_type: 'text_done', seq, created_at: ts });
}
