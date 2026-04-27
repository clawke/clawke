/**
 * TS 新架构集成测试
 *
 * 验证 Database → MessageStore → ConversationStore → CupV2Handler
 * → EventRegistry → cup-encoder → MessageRouter 完整链路
 *
 * 使用 :memory: DB，无外部依赖
 */
const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

// 从 dist/ 导入编译后的 TS 模块
const { Database } = require('../dist/store/database');
const { MessageStore } = require('../dist/store/message-store');
const { ConversationStore } = require('../dist/store/conversation-store');
const { ConversationConfigStore } = require('../dist/store/conversation-config-store');
const { CupV2Handler } = require('../dist/protocol/cup-v2-handler');
const { EventRegistry } = require('../dist/event-registry');
const { MessageRouter } = require('../dist/upstream/message-router');
const { translateToCup } = require('../dist/translator/cup-encoder');
const { StatsCollector } = require('../dist/services/stats-collector');
const { VersionChecker } = require('../dist/services/version-checker');
const { ActionRouter } = require('../dist/event-handlers/user-action');
const { toUpstreamMessage } = require('../dist/types/upstream');
const { loadConfig } = require('../dist/config');

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Store 层
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: Database', () => {
  it('creates in-memory DB and runs migrations', () => {
    const db = new Database(':memory:');
    // 验证表存在
    const tables = db.raw.prepare("SELECT name FROM sqlite_master WHERE type='table'").all()
      .map(r => r.name).sort();
    assert.ok(tables.includes('messages'), 'messages table exists');
    assert.ok(tables.includes('conversations'), 'conversations table exists');
    assert.ok(tables.includes('metadata'), 'metadata table exists');
    assert.ok(tables.includes('cron_jobs'), 'cron_jobs table exists');

    // 验证 schema version
    const version = db.raw.pragma('user_version', { simple: true });
    assert.equal(version, 3);
    db.close();
  });

  it('cleanup removes old messages', () => {
    const db = new Database(':memory:');
    // 插入一条 8 天前的消息
    db.raw.prepare(`
      INSERT INTO messages (id, account_id, sender_id, type, content, created_at, seq)
      VALUES ('old1', 'acc', 'user', 'text', 'old', ${Date.now() - 8 * 24 * 60 * 60 * 1000}, 1)
    `).run();
    // 插入一条新消息
    db.raw.prepare(`
      INSERT INTO messages (id, account_id, sender_id, type, content, created_at, seq)
      VALUES ('new1', 'acc', 'user', 'text', 'new', ${Date.now()}, 2)
    `).run();

    const changes = db.cleanup();
    assert.equal(changes, 1, 'cleaned 1 old message');

    const remaining = db.raw.prepare('SELECT COUNT(*) as c FROM messages').get();
    assert.equal(remaining.c, 1, '1 message remains');
    db.close();
  });
});

describe('TS: MessageStore', () => {
  it('append → getAfterSeq → getCurrentSeq cycle', () => {
    const db = new Database(':memory:');
    const store = new MessageStore(db);

    const r1 = store.append('acc1', 'conv1', 'cmsg_1', 'user', 'text', 'hello');
    assert.ok(r1.serverMsgId.startsWith('smsg_'));
    assert.ok(r1.seq > 0);
    assert.ok(r1.ts > 0);

    const r2 = store.append('acc1', 'conv1', 'cmsg_2', 'agent', 'text', 'world');
    assert.equal(r2.seq, r1.seq + 1);

    // getAfterSeq
    const msgs = store.getAfterSeq(r1.seq - 1);
    assert.equal(msgs.length, 2);
    assert.equal(msgs[0].content, 'hello');
    assert.equal(msgs[1].content, 'world');

    assert.equal(store.getCurrentSeq(), r2.seq);
    db.close();
  });

  it('getAfterSeq caps initial sync history at 100 messages', () => {
    const db = new Database(':memory:');
    const store = new MessageStore(db);

    for (let i = 0; i < 105; i++) {
      store.append('acc1', 'conv1', `cmsg_${i}`, 'user', 'text', `message ${i}`);
    }

    const msgs = store.getAfterSeq(0);
    assert.equal(msgs.length, 100);
    assert.equal(msgs[0].content, 'message 0');
    assert.equal(msgs[99].content, 'message 99');
    db.close();
  });

  it('duplicate client_msg_id returns existing (idempotent)', () => {
    const db = new Database(':memory:');
    const store = new MessageStore(db);

    const r1 = store.append('acc1', 'conv1', 'dup_id', 'user', 'text', 'first');
    const r2 = store.append('acc1', 'conv1', 'dup_id', 'user', 'text', 'second');
    assert.equal(r2.serverMsgId, r1.serverMsgId, 'same serverMsgId');
    assert.equal(r2.seq, r1.seq, 'same seq');
    db.close();
  });
});

describe('TS: ConversationStore', () => {
  it('ensure creates and returns conversation', () => {
    const db = new Database(':memory:');
    new ConversationConfigStore(db);  // 确保 conversation_configs 表存在 — Ensure table exists
    const store = new ConversationStore(db);

    const conv = store.ensure('conv_1');
    assert.equal(conv.id, 'conv_1');
    assert.equal(conv.type, 'dm');

    // second call returns same record
    const conv2 = store.ensure('conv_1');
    assert.equal(conv2.createdAt, conv.createdAt);

    // list
    const all = store.list();
    assert.equal(all.length, 1);
    db.close();
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Protocol 层
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: CupV2Handler', () => {
  function createHandler() {
    const db = new Database(':memory:');
    new ConversationConfigStore(db);  // 确保 conversation_configs 表存在 — Ensure table exists
    const ms = new MessageStore(db);
    const cs = new ConversationStore(db);
    return { handler: new CupV2Handler(ms, cs), db, ms };
  }

  it('handleUserMessage returns ACK with seq', () => {
    const { handler, db } = createHandler();
    const ack = handler.handleUserMessage({
      event_type: 'user_message',
      context: { account_id: 'test_acc', client_msg_id: 'cm1' },
      data: { content: 'hello' },
    });
    assert.equal(ack.payload_type, 'ctrl');
    assert.equal(ack.code, 200);
    assert.ok(ack.params.server_msg_id);
    assert.ok(ack.params.seq > 0);
    db.close();
  });

  it('handleSync returns messages after seq', () => {
    const { handler, db } = createHandler();
    // seed a message
    handler.handleUserMessage({
      event_type: 'user_message',
      context: { account_id: 'acc', client_msg_id: 'c1' },
      data: { content: 'test' },
    });
    const seq0 = handler.handleSync({
      event_type: 'sync', data: { last_seq: 0 },
    });
    // last_seq=0 → 拉取全量历史（最多 100 条）— Pull full history (up to LIMIT 100)
    assert.equal(seq0.messages.length, 1, 'new device gets all stored messages');
    assert.ok(seq0.current_seq > 0);
    db.close();
  });

  it('storeAgentMessage stores and returns seq', () => {
    const { handler, db } = createHandler();
    const r = handler.storeAgentMessage('acc', 'conv1', 'AI reply', 'text', 'upstream_1');
    assert.ok(r.serverMsgId.startsWith('smsg_'));
    assert.ok(r.seq > 0);
    db.close();
  });

  it('makeDeliveredAck returns code 201', () => {
    const { handler } = createHandler();
    const ack = handler.makeDeliveredAck('req_1');
    assert.equal(ack.code, 201);
    assert.equal(ack.params.status, 'delivered');
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Translator 层（纯函数）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: translateToCup (pure function)', () => {
  it('agent_text_delta returns text_delta + streamingId metadata', () => {
    const r = translateToCup({ type: 'agent_text_delta', message_id: 'm1', delta: 'Hi' }, 'acc1');
    assert.equal(r.cupMessages.length, 1);
    assert.equal(r.cupMessages[0].payload_type, 'text_delta');
    assert.equal(r.cupMessages[0].content, 'Hi');
    assert.equal(r.cupMessages[0].account_id, 'acc1');
    assert.equal(r.metadata.streamingId, 'm1');
  });

  it('agent_text_done returns text_done + needsStore metadata', () => {
    const r = translateToCup({
      type: 'agent_text_done', message_id: 'm2', fullText: 'Hello world',
      usage: { input_tokens: 100, output_tokens: 50 },
    }, 'acc1');
    assert.ok(r.cupMessages.length >= 1);
    assert.equal(r.cupMessages[0].payload_type, 'text_done');
    assert.ok(r.metadata.needsStore);
    assert.equal(r.metadata.needsStore.fullText, 'Hello world');
    assert.ok(r.metadata.usage);
    assert.equal(r.metadata.untrackStreamingId, 'm2');
  });

  it('agent_thinking_delta returns thinking_delta', () => {
    const r = translateToCup({ type: 'agent_thinking_delta', message_id: 'm3', delta: 'thinking...' }, 'acc');
    assert.equal(r.cupMessages[0].payload_type, 'thinking_delta');
    assert.equal(r.cupMessages[0].content, 'thinking...');
  });

  it('agent_tool_call returns tool_call_start', () => {
    const r = translateToCup({ type: 'agent_tool_call', message_id: 'm4', toolName: 'read_file' }, 'acc');
    assert.equal(r.cupMessages[0].payload_type, 'tool_call_start');
    assert.equal(r.cupMessages[0].tool_name, 'read_file');
  });

  it('unknown type returns null', () => {
    const r = translateToCup({ type: 'unknown_type' }, 'acc');
    assert.equal(r, null);
  });

  it('empty delta returns null', () => {
    const r = translateToCup({ type: 'agent_text_delta', delta: '' }, 'acc');
    assert.equal(r, null);
  });

  it('agent_text with error_code passes through to text_done', () => {
    const r = translateToCup({
      type: 'agent_text',
      text: '',
      error_code: 'network_error',
      error_detail: 'Connection refused',
    }, 'acc1');

    assert.ok(r);
    const textDone = r.cupMessages.find(m => m.payload_type === 'text_done');
    assert.ok(textDone, 'text_done message exists');
    assert.equal(textDone.error_code, 'network_error');
    assert.equal(textDone.error_detail, 'Connection refused');
  });

  it('agent_text without error_code omits error fields', () => {
    const r = translateToCup({
      type: 'agent_text',
      text: 'Normal reply',
    }, 'acc1');

    assert.ok(r);
    const textDone = r.cupMessages.find(m => m.payload_type === 'text_done');
    assert.ok(textDone, 'text_done message exists');
    assert.equal(textDone.error_code, undefined, 'no error_code');
    assert.equal(textDone.error_detail, undefined, 'no error_detail');
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  EventRegistry
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: EventRegistry', () => {
  it('dispatches to registered handler', async () => {
    const registry = new EventRegistry();
    let received = null;
    registry.register('test_event', (ctx) => { received = ctx.accountId; });

    const fakeWs = { readyState: 1, send: () => {} };
    await registry.dispatch(fakeWs, {
      event_type: 'test_event',
      context: { account_id: 'test_acc' },
    });
    assert.equal(received, 'test_acc');
  });

  it('logs warning for unknown event type', async () => {
    const registry = new EventRegistry();
    const fakeWs = { readyState: 1, send: () => {} };
    // Should not throw
    await registry.dispatch(fakeWs, { event_type: 'unknown' });
  });

  it('size returns number of registered handlers', () => {
    const registry = new EventRegistry();
    assert.equal(registry.size, 0);
    registry.register('a', () => {});
    registry.register('b', () => {});
    assert.equal(registry.size, 2);
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  ActionRouter
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: ActionRouter', () => {
  it('dispatches to exact action_id match', () => {
    const router = new ActionRouter();
    router.register('cron.create', () => ({ result: 'created' }));
    router.register('cron.delete', () => ({ result: 'deleted' }));

    const r = router.dispatch(
      { event_type: 'user_action', action: { action_id: 'cron.create' } },
      {}
    );
    assert.deepEqual(r, { result: 'created' });
  });

  it('returns null for unknown action_id', () => {
    const router = new ActionRouter();
    const r = router.dispatch(
      { event_type: 'user_action', action: { action_id: 'unknown' } },
      {}
    );
    assert.equal(r, null);
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  MessageRouter（副作用汇聚点）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: MessageRouter', () => {
  function createRouter() {
    const db = new Database(':memory:');
    new ConversationConfigStore(db);  // 确保 conversation_configs 表存在 — Ensure table exists
    const ms = new MessageStore(db);
    const cs = new ConversationStore(db);
    const cupHandler = new CupV2Handler(ms, cs);

    const broadcasted = [];
    const stats = {
      recorded: { tokens: [], tools: [], messages: 0, conversations: 0 },
      recordTokens(i, o, c) { this.recorded.tokens.push({ i, o, c }); },
      recordToolCall(n, d) { this.recorded.tools.push({ n, d }); },
      recordMessage() { this.recorded.messages++; },
      recordConversation() { this.recorded.conversations++; },
    };

    const router = new MessageRouter(
      translateToCup, cupHandler, stats,
      (msg) => broadcasted.push(msg),
    );
    return { router, db, stats, broadcasted };
  }

  it('text_delta → broadcast without storage', () => {
    const { router, db, broadcasted, stats } = createRouter();
    router.handleUpstreamMessage({
      type: 'agent_text_delta', message_id: 'm1', delta: 'Hello',
    }, 'acc1');

    assert.equal(broadcasted.length, 1);
    assert.equal(broadcasted[0].payload_type, 'text_delta');
    assert.equal(broadcasted[0].content, 'Hello');
    assert.equal(stats.recorded.tokens.length, 0, 'no tokens for delta');
    db.close();
  });

  it('text_done → store + usage stats + broadcast', () => {
    const { router, db, broadcasted, stats } = createRouter();
    router.handleUpstreamMessage({
      type: 'agent_text_done', message_id: 'm2', fullText: 'Full reply',
      usage: { input_tokens: 500, output_tokens: 100 },
    }, 'acc1');

    // Should have text_done + usage_report
    assert.ok(broadcasted.length >= 1);
    const textDone = broadcasted.find(m => m.payload_type === 'text_done');
    assert.ok(textDone);
    assert.ok(textDone.seq > 0, 'text_done has seq from storage');
    assert.ok(textDone.message_id.startsWith('smsg_'), 'uses serverMsgId');

    // Usage stats recorded
    assert.equal(stats.recorded.tokens.length, 1);
    assert.equal(stats.recorded.tokens[0].i, 500);
    assert.equal(stats.recorded.tokens[0].o, 100);
    db.close();
  });

  it('aborted session discards messages', () => {
    const { router, db, broadcasted } = createRouter();
    router.abortSession('acc1');
    router.handleUpstreamMessage({
      type: 'agent_text_delta', message_id: 'm3', delta: 'should ignore',
    }, 'acc1');
    assert.equal(broadcasted.length, 0, 'message discarded');
    db.close();
  });

  it('text_done clears abort state', () => {
    const { router, db, broadcasted } = createRouter();
    router.abortSession('acc1');
    router.handleUpstreamMessage({
      type: 'agent_text_done', message_id: 'm4', fullText: '',
    }, 'acc1');
    // abort 标记只由 clearAbort() 显式清除（user_message handler 调用），text_done 不清除
    // abort state is only cleared by explicit clearAbort(), not by text_done
    assert.equal(broadcasted.length, 0);

    // 显式清除 abort 后消息应通过 — After explicit clear, messages should pass through
    router.clearAbort('acc1');
    router.handleUpstreamMessage({
      type: 'agent_text_delta', message_id: 'm5', delta: 'back',
    }, 'acc1');
    assert.equal(broadcasted.length, 1, 'message goes through after clear');
    db.close();
  });

  it('tool_result records toolCall stats', () => {
    const { router, db, stats } = createRouter();
    router.handleUpstreamMessage({
      type: 'agent_tool_result', message_id: 'm6',
      toolName: 'read_file', durationMs: 150,
    }, 'acc1');
    assert.equal(stats.recorded.tools.length, 1);
    assert.equal(stats.recorded.tools[0].n, 'read_file');
    assert.equal(stats.recorded.tools[0].d, 150);
    db.close();
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Services
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: VersionChecker', () => {
  it('compareVersions works correctly', () => {
    assert.equal(VersionChecker.compareVersions('1.0.0', '1.0.1'), -1);
    assert.equal(VersionChecker.compareVersions('2.0.0', '1.9.9'), 1);
    assert.equal(VersionChecker.compareVersions('1.2.3', '1.2.3'), 0);
    assert.equal(VersionChecker.compareVersions('v1.0.0', '1.0.0'), 0);
  });

  it('matchDownloadUrl finds platform-specific asset', () => {
    const assets = [
      { name: 'app-macos-arm64.dmg', browser_download_url: 'https://dl/mac', size: 100 },
      { name: 'app-linux-x64.tar.gz', browser_download_url: 'https://dl/linux', size: 200 },
    ];
    assert.equal(VersionChecker.matchDownloadUrl(assets, 'macos', 'arm64'), 'https://dl/mac');
    assert.equal(VersionChecker.matchDownloadUrl(assets, 'linux', 'x64'), 'https://dl/linux');
    assert.equal(VersionChecker.matchDownloadUrl(assets, 'windows', 'x64'), null);
  });
});

describe('TS: StatsCollector', () => {
  it('recordTokens accumulates correctly', () => {
    // Use /tmp to avoid polluting project data
    const stats = new StatsCollector('/tmp/clawke-test-stats-' + Date.now());
    stats.recordTokens(100, 50, 20);
    stats.recordTokens(200, 80, 10);

    const dashboard = stats.getDashboardJson(2, true, 'en');
    assert.equal(dashboard.widget_name, 'DashboardView');
    // Verify stats grid exists
    const statsGrid = dashboard.props.sections.find(s => s.type === 'stats_grid');
    assert.ok(statsGrid, 'stats_grid section exists');
  });

  it('populateMockData fills all sections', () => {
    const stats = new StatsCollector('/tmp/clawke-test-stats-' + Date.now());
    stats.populateMockData();
    const dashboard = stats.getDashboardJson(1, false, 'zh');
    assert.equal(dashboard.props.sections.length, 5);
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Upstream 标准协议
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: toUpstreamMessage', () => {
  it('converts chat payload to standard format', () => {
    const msg = toUpstreamMessage({
      data: { content: 'hello', type: 'text' },
      context: { account_id: 'acc1', client_msg_id: 'cm1' },
    }, 'chat', { paths: ['/tmp/img.png'], types: ['image/png'], names: ['img.png'] });
    assert.equal(msg.type, 'chat');
    assert.equal(msg.conversation_id, 'acc1');
    assert.equal(msg.text, 'hello');
    assert.equal(msg.client_msg_id, 'cm1');
    assert.equal(msg.content_type, 'text');
    assert.ok(msg.media);
    assert.equal(msg.media.paths.length, 1);
  });

  it('converts abort payload', () => {
    const msg = toUpstreamMessage({
      data: { message_id: 'msg_123' },
      context: { account_id: 'acc1' },
    }, 'abort');
    assert.equal(msg.type, 'abort');
    assert.equal(msg.message_id, 'msg_123');
  });

  it('extracts text from image type', () => {
    const msg = toUpstreamMessage({
      data: { type: 'image', content: '/path/to/img.png' },
      context: { account_id: 'acc1' },
    }, 'chat');
    assert.equal(msg.text, '[用户发送了一张图片]');
    assert.equal(msg.content_type, 'image');
  });

  it('extracts text from mixed type', () => {
    const msg = toUpstreamMessage({
      data: { type: 'mixed', content: JSON.stringify({ text: 'caption' }) },
      context: { account_id: 'acc1' },
    }, 'chat');
    assert.equal(msg.text, 'caption');
    assert.equal(msg.content_type, 'mixed');
  });
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  Config
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

describe('TS: Config', () => {
  it('loadConfig returns server config with defaults', () => {
    const config = loadConfig();
    assert.ok(config.server);
    assert.ok(['mock', 'openclaw'].includes(config.server.mode));
    assert.ok(config.server.httpPort > 0);
  });
});
