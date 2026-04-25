#!/usr/bin/env node
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const requireFromServer = createRequire(new URL('../../../server/package.json', import.meta.url));
const WebSocket = requireFromServer('ws');

const args = parseArgs(process.argv.slice(2));
const casePath = required(args, 'case');
const upstreamUrl = required(args, 'upstream-url');
const logPath = required(args, 'log');
const testCase = JSON.parse(fs.readFileSync(casePath, 'utf8'));
const setup = testCase.setup || {};
const accountId = setup.accountId || 'e2e_mock';
const agentName = setup.agentName || 'E2E Mock Gateway';

fs.mkdirSync(path.dirname(logPath), { recursive: true });
const logStream = fs.createWriteStream(logPath, { flags: 'a' });

function log(message) {
  const line = `[mock-gateway] ${new Date().toISOString()} ${message}`;
  console.log(line);
  logStream.write(`${line}\n`);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    out[argv[i].replace(/^--/, '')] = argv[i + 1];
  }
  return out;
}

function required(map, key) {
  if (!map[key]) {
    console.error(`Missing --${key}`);
    process.exit(2);
  }
  return map[key];
}

function withConversation(reply, incoming) {
  return {
    ...reply,
    conversation_id: incoming.conversation_id || accountId,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendReplies(ws, incoming) {
  const rule = testCase.mockGateway?.onUserMessage;
  if (!rule) return;
  const text = incoming.text || '';
  if (rule.contains && !text.includes(rule.contains)) {
    log(`ignored chat text="${text}"`);
    return;
  }

  for (const reply of rule.replies || []) {
    await sleep(reply.delayMs || 40);
    const payload = withConversation(reply, incoming);
    log(`send ${JSON.stringify(payload)}`);
    ws.send(JSON.stringify(payload));
  }
}

function connect() {
  log(`connecting ${upstreamUrl}`);
  const ws = new WebSocket(upstreamUrl);

  ws.on('open', () => {
    const identify = { type: 'identify', accountId, agentName };
    log(`identify ${JSON.stringify(identify)}`);
    ws.send(JSON.stringify(identify));
  });

  ws.on('message', async (raw) => {
    const text = raw.toString();
    log(`recv ${text}`);
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      log('invalid json ignored');
      return;
    }
    if (msg.type === 'chat') {
      await sendReplies(ws, msg);
    }
  });

  ws.on('close', () => {
    log('closed');
    process.exit(0);
  });

  ws.on('error', (err) => {
    log(`error ${err.message}`);
    process.exit(1);
  });
}

process.on('SIGTERM', () => {
  log('SIGTERM');
  process.exit(0);
});

connect();
