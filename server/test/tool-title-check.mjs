#!/usr/bin/env node
/**
 * 打印 tool_call_start 的 tool_title 字段
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

const ws = new WebSocket(`ws://127.0.0.1:8780/ws${token ? '?token=' + token : ''}`);

ws.on('message', (raw) => {
  const msg = JSON.parse(raw.toString());
  if (msg.payload_type === 'typing_start') {
    console.log('📥 typing_start: ⌨️ AI 开始处理');
  }
  if (msg.payload_type === 'tool_call_start') {
    console.log('📥 tool_call_start:');
    console.log(`   tool_name:  ${msg.tool_name || '(empty)'}`);
    console.log(`   tool_title: ${msg.tool_title || '(empty)'}`);
    console.log(`   call_id:    ${msg.tool_call_id || '?'}`);
  }
  if (msg.payload_type === 'text_done') {
    console.log('\n✅ text_done — 测试完成');
    ws.close();
    process.exit(0);
  }
});

ws.on('open', () => {
  ws.send(JSON.stringify({
    id: 's', protocol: 'cup_v2', event_type: 'sync',
    data: { last_seq: 0, app_version: '0.1.0', platform: 'test' },
  }));
  setTimeout(async () => {
    const resp = await fetch('http://127.0.0.1:8780/api/conversations', {
      headers: token ? { 'Authorization': `Bearer ${token}` } : {},
    });
    const convs = await resp.json();
    const conv = convs[0];
    console.log(`📤 发送: "查上海天气"\n`);
    ws.send(JSON.stringify({
      id: 't1', protocol: 'cup_v2', event_type: 'user_message',
      context: {
        client_msg_id: 't1', account_id: conv.account_id,
        conversation_id: conv.id, device_id: 'test',
      },
      data: { type: 'text', content: '查上海天气' },
    }));
  }, 2000);
});

setTimeout(() => process.exit(1), 30000);
