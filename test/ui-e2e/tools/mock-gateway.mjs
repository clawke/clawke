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
const consumedInteractions = new Set();

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
  const { delayMs, ...wireReply } = reply;
  return {
    ...wireReply,
    conversation_id: incoming.conversation_id || accountId,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendReplyList(ws, incoming, replies) {
  for (const reply of replies || []) {
    await sleep(reply.delayMs || 40);
    const payload = withConversation(reply, incoming);
    log(`send ${JSON.stringify(payload)}`);
    ws.send(JSON.stringify(payload));
  }
}

function incomingText(msg) {
  return String(msg.text || msg.response || msg.choice || '');
}

function matches(on, incoming) {
  if (on.type && incoming.type !== on.type) return false;
  if (on.text && incoming.text !== on.text) return false;
  if (on.equals && incomingText(incoming) !== on.equals) return false;
  if (on.contains && !incomingText(incoming).includes(on.contains)) return false;
  if (on.choice && incoming.choice !== on.choice) return false;
  if (on.response && incoming.response !== on.response) return false;
  return true;
}

async function sendScriptedInteraction(ws, incoming) {
  const interactions = testCase.mockGateway?.interactions;
  if (!Array.isArray(interactions)) return false;

  for (let i = 0; i < interactions.length; i += 1) {
    if (consumedInteractions.has(i)) continue;
    const interaction = interactions[i];
    if (!matches(interaction.on || {}, incoming)) continue;
    consumedInteractions.add(i);
    await sendReplyList(ws, incoming, interaction.replies || []);
    return true;
  }
  log(`unmatched ${JSON.stringify(incoming)}`);
  return false;
}

async function sendLegacyUserMessageReplies(ws, incoming) {
  const rule = testCase.mockGateway?.onUserMessage;
  if (!rule || incoming.type !== 'chat') return false;
  const text = incoming.text || '';
  if (rule.contains && !text.includes(rule.contains)) {
    log(`ignored chat text="${text}"`);
    return true;
  }

  await sendReplyList(ws, incoming, rule.replies || []);
  return true;
}

function sendTransientResponse(ws, incoming) {
  if (incoming.type === 'query_models') {
    ws.send(JSON.stringify({ type: 'models_response', models: ['e2e-mock-model'] }));
    return true;
  }
  if (incoming.type === 'query_skills') {
    ws.send(JSON.stringify({ type: 'skills_response', skills: [] }));
    return true;
  }
  if (incoming.type === 'task_list') {
    ws.send(JSON.stringify({
      type: 'task_list_response',
      request_id: incoming.request_id,
      tasks: [],
    }));
    return true;
  }
  return false;
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
    if (sendTransientResponse(ws, msg)) return;
    if (await sendScriptedInteraction(ws, msg)) return;
    await sendLegacyUserMessageReplies(ws, msg);
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
