#!/usr/bin/env node
/**
 * tool-call-trace.mjs — 测试工具调用消息是否正确传递到客户端
 * 发送 "帮我查杭州天气" → 监听所有 CUP 消息 → 打印 tool_call_start / tool_call_done
 */
import WebSocket from 'ws';
import { readFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

let token = '';
try {
  const cfg = JSON.parse(readFileSync(join(homedir(), '.clawke', 'clawke.json'), 'utf-8'));
  token = cfg.relay?.token || '';
} catch {}

const WS_URL = `ws://127.0.0.1:8780/ws${token ? '?token=' + token : ''}`;
const TIMEOUT_MS = 60000;

let conversationId = null;
let accountId = null;
let toolMessages = [];
let textDeltaCount = 0;

async function main() {
  console.log('🧪 Tool Call Trace Test\n');

  const ws = new WebSocket(WS_URL);

  const timeout = setTimeout(() => {
    console.log('\n⏰ 超时');
    printResult();
    ws.close();
    process.exit(1);
  }, TIMEOUT_MS);

  function printResult() {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`工具相关消息: ${toolMessages.length}`);
    for (const m of toolMessages) {
      console.log(`  ${m.payload_type}: tool_name=${m.tool_name || '?'}, tool_call_id=${m.tool_call_id || '?'}`);
      if (m.duration_ms !== undefined) console.log(`    duration_ms=${m.duration_ms}, status=${m.status}`);
    }
    console.log(`text_delta 数量: ${textDeltaCount}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━');
    const pass = toolMessages.length > 0 && toolMessages.some(m => m.payload_type === 'tool_call_start' && m.tool_name);
    console.log(pass ? '\n✅ PASS — 工具调用消息正确传递' : '\n❌ FAIL — 未收到 tool_call_start 或缺少 tool_name');
    return pass;
  }

  ws.on('open', () => {
    console.log('✅ 已连接');
    ws.send(JSON.stringify({
      id: 'sync_init',
      protocol: 'cup_v2',
      event_type: 'sync',
      data: { last_seq: 0, app_version: '0.1.0', platform: 'test' },
    }));
  });

  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    const type = msg.payload_type || msg.type;

    if (type === 'system_status' && msg.status === 'ai_connected') {
      accountId = msg.account_id;
    }

    if (type === 'sync_response') {
      fetchConversations();
      return;
    }

    // 监听所有消息
    if (type === 'tool_call_start' || type === 'tool_call_done') {
      toolMessages.push(msg);
      console.log(`📥 ${type}: tool_name=${msg.tool_name || '?'}`);
    }

    if (type === 'text_delta') {
      textDeltaCount++;
      if (textDeltaCount === 1) console.log('📥 首个 text_delta 到达');
    }

    if (type === 'text_done' && textDeltaCount > 0) {
      console.log('📄 text_done');
      setTimeout(() => {
        const pass = printResult();
        clearTimeout(timeout);
        ws.close();
        process.exit(pass ? 0 : 1);
      }, 500);
    }
  });

  async function fetchConversations() {
    try {
      const resp = await fetch('http://127.0.0.1:8780/api/conversations', {
        headers: token ? { 'Authorization': `Bearer ${token}` } : {},
      });
      const data = await resp.json();
      const convs = Array.isArray(data) ? data : [];
      const conv = convs.find(c => c.account_id === accountId) || convs[0];
      if (conv) {
        conversationId = conv.id;
        accountId = accountId || conv.account_id;
        console.log(`📋 会话: ${conversationId}\n`);
        sendMessage();
      } else {
        setTimeout(fetchConversations, 3000);
      }
    } catch (e) {
      setTimeout(fetchConversations, 3000);
    }
  }

  function sendMessage() {
    const msgId = `test_tool_${Date.now()}`;
    console.log('📤 发送: "帮我查北京今天天气"');
    ws.send(JSON.stringify({
      id: msgId,
      protocol: 'cup_v2',
      event_type: 'user_message',
      context: {
        client_msg_id: msgId,
        account_id: accountId,
        conversation_id: conversationId,
        device_id: 'test_device',
      },
      data: {
        type: 'text',
        content: '帮我查北京今天天气',
      },
    }));
    console.log('⏳ 等待工具调用...\n');
  }

  ws.on('error', (err) => {
    console.error(`❌ WebSocket 错误: ${err.message}`);
    process.exit(1);
  });
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
