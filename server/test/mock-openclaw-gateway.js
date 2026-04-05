const WebSocket = require('ws');

const UPSTREAM_URL = 'ws://127.0.0.1:8766';

console.log(`[Mock Gateway] Connecting to Clawke Server: ${UPSTREAM_URL}`);
const ws = new WebSocket(UPSTREAM_URL);

const delay = ms => new Promise(res => setTimeout(res, ms));

ws.on('open', async () => {
  console.log('[Mock Gateway] Connected to Clawke Server');

  // 等待 2 秒让用户先从 Flutter 发消息
  await delay(2000);

  // 模拟流式文本输出
  const msgId = `msg_${Date.now()}`;
  const text = '好的，这是你要的代码示例：';

  console.log(`[Mock Gateway] Starting stream output msgId=${msgId}`);
  for (const char of text) {
    ws.send(JSON.stringify({
      type: 'agent_text_delta',
      message_id: msgId,
      delta: char,
      account_id: 'test_conv_123'
    }));
    await delay(50);
  }

  // 发送流式结束 + 包含代码块的完整文本
  ws.send(JSON.stringify({
    type: 'agent_text_done',
    message_id: msgId,
    fullText: '好的，这是你要的代码示例：\n\n```dart\nimport \'package:flutter/material.dart\';\n\nvoid main() {\n  runApp(const MyApp());\n}\n```',
    account_id: 'test_conv_123'
  }));

  console.log('[Mock Gateway] Stream output complete');
});

ws.on('message', (raw) => {
  console.log('[Mock Gateway] Received Clawke Server message:', raw.toString());
});

ws.on('close', () => console.log('[Mock Gateway] Connection closed'));
ws.on('error', (err) => console.error('[Mock Gateway] Error:', err.message));
