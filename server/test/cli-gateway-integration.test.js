/**
 * CLI Gateway 集成测试
 *
 * 启动 MODE=cli 服务端，通过 WebSocket 连接发送消息，
 * 验证 Claude Code 子进程的输出能正确转译为 CUP 协议返回给客户端。
 *
 * 运行：node --test server/test/cli-gateway-integration.test.js
 */
import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const SERVER_PORT = 8780;

/** 从 ~/.clawke/clawke.json 读取 relay token */
function getServerToken() {
  try {
    const cfgPath = join(homedir(), '.clawke', 'clawke.json');
    const cfg = JSON.parse(readFileSync(cfgPath, 'utf-8'));
    return cfg.relay?.token || '';
  } catch {
    return '';
  }
}

const TOKEN = getServerToken();
const WS_URL = `ws://127.0.0.1:${SERVER_PORT}/ws?token=${encodeURIComponent(TOKEN)}`;

/** 等待端口可用 */
async function waitForPort(port, timeoutMs = 30000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/health`);
      if (res.ok) return true;
    } catch {}
    await sleep(500);
  }
  throw new Error(`Port ${port} not available after ${timeoutMs}ms`);
}

describe('CLI Gateway Integration', { timeout: 120000 }, () => {
  let serverProc;
  let ws;
  const allMessages = [];

  before(async () => {
    console.log('🚀 Starting server with MODE=cli...');
    console.log(`   Token: ${TOKEN ? TOKEN.slice(0, 8) + '...' : '(none)'}`);

    // 杀残留进程
    try {
      const { execSync } = await import('node:child_process');
      execSync('lsof -ti:8780 | xargs kill -9 2>/dev/null || true', { stdio: 'ignore' });
      execSync('lsof -ti:8781 | xargs kill -9 2>/dev/null || true', { stdio: 'ignore' });
      await sleep(1000);
    } catch {}

    serverProc = spawn('node', ['dist/index.js'], {
      cwd: new URL('../../server', import.meta.url).pathname,
      env: {
        ...process.env,
        MODE: 'cli',
        CLI_CWD: process.env.CLI_CWD || process.cwd(),
        CLI_PERMISSION_MODE: 'default',
      },
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    serverProc.stdout.on('data', (d) => {
      for (const line of d.toString().trim().split('\n')) {
        if (!line.includes('[frpc]') && !line.includes('[VersionChecker]')) {
          console.log(`  [S] ${line}`);
        }
      }
    });
    serverProc.stderr.on('data', (d) => {
      for (const line of d.toString().trim().split('\n')) {
        if (!line.includes('[frpc]') && !line.includes('[VersionChecker]')) {
          console.log(`  [S:err] ${line}`);
        }
      }
    });

    console.log('⏳ Waiting for server...');
    await waitForPort(SERVER_PORT, 30000);
    console.log('✅ Server ready');

    // 等 Claude Code 初始化
    console.log('⏳ Waiting for Claude Code init (8s)...');
    await sleep(8000);
  });

  after(async () => {
    console.log('🧹 Cleaning up...');
    if (ws && ws.readyState <= 1) ws.close();
    if (serverProc) {
      serverProc.kill('SIGTERM');
      await sleep(2000);
      if (!serverProc.killed) serverProc.kill('SIGKILL');
    }
  });

  it('should connect via WebSocket with token', async () => {
    console.log(`📡 Connecting to ${WS_URL.replace(TOKEN, TOKEN.slice(0, 8) + '...')}...`);

    ws = new WebSocket(WS_URL);

    await new Promise((resolve, reject) => {
      ws.addEventListener('open', () => {
        console.log('✅ WebSocket connected');
        resolve();
      });
      ws.addEventListener('error', (e) => {
        console.error('❌ WebSocket error:', e);
        reject(new Error('WebSocket connection failed'));
      });
      setTimeout(() => reject(new Error('WebSocket connect timeout')), 5000);
    });

    assert.equal(ws.readyState, 1, 'WebSocket should be OPEN');

    // 监听所有消息
    ws.addEventListener('message', (event) => {
      try {
        const msg = JSON.parse(event.data);
        allMessages.push(msg);
        console.log(`  📩 ${msg.payload_type || msg.event_type || 'unknown'}: ${JSON.stringify(msg).slice(0, 120)}`);
      } catch {}
    });

    // 等收 ai_connected
    await sleep(3000);

    const aiConnected = allMessages.find(
      (m) => m.payload_type === 'system_status' && m.status === 'ai_connected'
    );
    if (aiConnected) {
      console.log(`✅ ai_connected: agent=${aiConnected.agent_name}`);
    } else {
      console.log('⚠️  ai_connected not received yet (Claude may still be loading)');
    }
  });

  it('should send message and get CUP response from Claude Code', async () => {
    assert.ok(ws && ws.readyState === 1, 'WebSocket must be open');

    // 清空消息
    allMessages.length = 0;

    const userMsg = {
      event_type: 'user_message',
      id: `test_${Date.now()}`,
      context: { account_id: 'cli', client_msg_id: `cmsg_${Date.now()}` },
      data: { text: 'Say exactly "hello from clawke" and nothing else.', type: 'text' },
    };

    console.log('📤 Sending: "Say exactly hello from clawke..."');
    ws.send(JSON.stringify(userMsg));

    // 轮询等待 text_delta 或任何 CUP 响应（最多 60 秒）
    console.log('⏳ Waiting for Claude Code response (max 60s)...');
    const deadline = Date.now() + 60000;
    let gotTextDelta = false;
    let gotTextDone = false;
    let gotPermissionRequest = false;
    let gotThinking = false;

    while (Date.now() < deadline) {
      await sleep(1000);

      for (const m of allMessages) {
        if (m.payload_type === 'text_delta' && m.content) gotTextDelta = true;
        if (m.payload_type === 'text_done') gotTextDone = true;
        if (m.payload_type === 'thinking_delta') gotThinking = true;
        if (m.payload_type === 'ui_component' && m.component?.widget_name === 'ActionConfirmation') {
          gotPermissionRequest = true;
          // 自动审批
          const requestId = m.component.props?.request_id;
          if (requestId) {
            console.log(`  🔐 Auto-approving permission: ${m.component.props.tool_name}`);
            ws.send(JSON.stringify({
              event_type: 'user_action',
              id: `action_${Date.now()}`,
              context: { account_id: 'cli' },
              action: { action_id: 'cli_approve_tool', data: { request_id: requestId } },
            }));
          }
        }
      }

      if (gotTextDelta) {
        const textMsg = allMessages.find(m => m.payload_type === 'text_delta' && m.content);
        console.log(`✅ text_delta received: "${textMsg.content.slice(0, 80)}"`);
        break;
      }

      if (gotThinking) {
        console.log('  💭 thinking_delta received (Claude is thinking...)');
      }

      // 定期报告
      if ((Date.now() - (deadline - 60000)) % 10000 < 1000) {
        console.log(`  ⏳ ${Math.ceil((deadline - Date.now()) / 1000)}s remaining, ${allMessages.length} messages so far`);
      }
    }

    // 结果验证
    console.log(`\n📊 Results: ${allMessages.length} total CUP messages`);
    const payloadTypes = [...new Set(allMessages.map(m => m.payload_type).filter(Boolean))];
    console.log(`   Payload types: ${payloadTypes.join(', ')}`);

    if (gotTextDelta) {
      console.log('✅ PASS: text_delta received — full pipeline working');
      const td = allMessages.find(m => m.payload_type === 'text_delta');
      assert.ok(td.content, 'text_delta should have content');
      assert.equal(td.account_id, 'cli', 'account_id should be cli');
    } else if (gotThinking) {
      console.log('✅ PASS: thinking_delta received — pipeline working (Claude is reasoning)');
    } else if (gotPermissionRequest) {
      console.log('✅ PASS: permission request received — pipeline working (Claude needs approval)');
    } else if (allMessages.length > 0) {
      console.log('⚠️  Got CUP messages but no text_delta/thinking_delta:');
      for (const m of allMessages.slice(0, 10)) {
        console.log(`   ${m.payload_type}: ${JSON.stringify(m).slice(0, 150)}`);
      }
      // 如果有任何有效的 CUP 消息，管道是通的
      const cupMsgs = allMessages.filter(m => m.payload_type);
      if (cupMsgs.length > 0) {
        console.log('✅ Pipeline is functional (CUP messages flowing)');
      } else {
        assert.fail('No valid CUP messages received');
      }
    } else {
      assert.fail('No messages received at all — pipeline broken');
    }

    // 如果有 text_done，说明完整对话完成
    if (gotTextDone) {
      console.log('✅ text_done received — complete round trip confirmed');
    }
  });
});
