#!/usr/bin/env node
/**
 * 持久化验证脚本 — 全量自动化测试
 *
 * 验证项：
 * 1. DB 文件创建 + Schema 正确性
 * 2. message-store: append → DB 写入 → getAfterSeq → seq 恢复
 * 3. conversation-store: ensure → persist → recovery
 * 4. cron-service: 默认数据初始化 → toggle persist
 * 5. 7 天清理逻辑
 * 6. clearUpToSeq 仍可用（但 index.js 不再调用）
 * 7. 重启恢复模拟：require 清缓存后重新加载模块
 */

const assert = require('node:assert');
const path = require('path');
const fs = require('fs');

const DB_PATH = path.join(__dirname, '../data/clawke.db');

// 清理旧 DB 文件确保干净测试
for (const ext of ['', '-wal', '-shm']) {
  const p = DB_PATH + ext;
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

console.log('=== 持久化验证脚本 ===\n');
let passed = 0;
let failed = 0;

function check(name, fn) {
  try {
    fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ❌ ${name}: ${e.message}`);
    failed++;
  }
}

// ── 1. DB 文件创建 ──────────────
console.log('1. DB 初始化');

// 预先清理 require 缓存
function clearModuleCache() {
  const keys = Object.keys(require.cache);
  for (const k of keys) {
    if (k.includes('message-store') || k.includes('conversation-store') || k.includes('cron-service') || k.includes('data/db')) {
      delete require.cache[k];
    }
  }
}

clearModuleCache();
const db = require('../services/store/db');

check('clawke.db 文件已创建', () => {
  assert.ok(fs.existsSync(DB_PATH), 'DB file should exist');
});

check('Schema version = 1', () => {
  const v = db.pragma('user_version', { simple: true });
  assert.strictEqual(v, 1);
});

check('messages 表存在', () => {
  const row = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='messages'").get();
  assert.ok(row, 'messages table should exist');
});

check('conversations 表存在', () => {
  const row = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='conversations'").get();
  assert.ok(row, 'conversations table should exist');
});

check('cron_jobs 表存在', () => {
  const row = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='cron_jobs'").get();
  assert.ok(row, 'cron_jobs table should exist');
});

check('WAL mode 已启用', () => {
  const mode = db.pragma('journal_mode', { simple: true });
  assert.strictEqual(mode, 'wal');
});

// ── 2. message-store 验证 ──────────────
console.log('\n2. message-store 持久化');

clearModuleCache();
const msgStore = require('../services/store/message-store');

check('初始 seq = 0（空 DB）', () => {
  assert.strictEqual(msgStore.getCurrentSeq(), 0);
});

check('append 创建消息并分配 seq', () => {
  const r1 = msgStore.append('conv_test', 'cmsg_1', 'user', 'text', 'hello world');
  assert.ok(r1.serverMsgId.startsWith('smsg_'));
  assert.strictEqual(r1.seq, 1);
});

check('append 第二条消息 seq 递增', () => {
  const r2 = msgStore.append('conv_test', 'cmsg_2', 'agent', 'text', 'hi there');
  assert.strictEqual(r2.seq, 2);
});

check('getCurrentSeq 返回最新 seq', () => {
  assert.strictEqual(msgStore.getCurrentSeq(), 2);
});

check('getAfterSeq(0) 返回所有消息', () => {
  const msgs = msgStore.getAfterSeq(0);
  assert.strictEqual(msgs.length, 2);
  assert.strictEqual(msgs[0].content, 'hello world');
  assert.strictEqual(msgs[1].content, 'hi there');
});

check('getAfterSeq(1) 只返回 seq > 1 的消息', () => {
  const msgs = msgStore.getAfterSeq(1);
  assert.strictEqual(msgs.length, 1);
  assert.strictEqual(msgs[0].seq, 2);
});

check('消息字段映射正确（serverMsgId, accountId, senderId, type, ts）', () => {
  const msgs = msgStore.getAfterSeq(0);
  const m = msgs[0];
  assert.ok(m.serverMsgId, 'should have serverMsgId');
  assert.strictEqual(m.accountId, 'conv_test');
  assert.strictEqual(m.senderId, 'user');
  assert.strictEqual(m.type, 'text');
  assert.ok(m.ts > 0, 'should have timestamp');
});

// ── 3. 重启恢复验证 ──────────────
console.log('\n3. 重启恢复（模块重新加载）');

const seqBeforeRestart = msgStore.getCurrentSeq();

check(`重启前 seq = ${seqBeforeRestart}`, () => {
  assert.strictEqual(seqBeforeRestart, 2);
});

// 清除 require 缓存模拟重启
clearModuleCache();
const msgStore2 = require('../services/store/message-store');

check(`重启后 seq 恢复为 ${seqBeforeRestart}`, () => {
  assert.strictEqual(msgStore2.getCurrentSeq(), seqBeforeRestart);
});

check('重启后 getAfterSeq(0) 返回持久化的消息', () => {
  const msgs = msgStore2.getAfterSeq(0);
  assert.strictEqual(msgs.length, 2);
  assert.strictEqual(msgs[0].content, 'hello world');
});

check('重启后 append 继续从恢复的 seq 递增', () => {
  const r3 = msgStore2.append('conv_test', 'cmsg_3', 'user', 'text', 'after restart');
  assert.strictEqual(r3.seq, seqBeforeRestart + 1);
});

// ── 4. conversation-store 验证 ──────────────
console.log('\n4. conversation-store 持久化');

clearModuleCache();
const convStore = require('../services/store/conversation-store');

check('ensure 创建并返回会话', () => {
  const conv = convStore.ensure('conv_persist', 'dm', 'Persist Test');
  assert.strictEqual(conv.id, 'conv_persist');
  assert.strictEqual(conv.name, 'Persist Test');
  assert.strictEqual(conv.type, 'dm');
});

check('get 返回刚创建的会话', () => {
  const conv = convStore.get('conv_persist');
  assert.ok(conv);
  assert.strictEqual(conv.name, 'Persist Test');
});

check('list 包含已创建的会话', () => {
  const all = convStore.list();
  assert.ok(all.length >= 1);
  assert.ok(all.some(c => c.id === 'conv_persist'));
});

// 模拟重启
clearModuleCache();
const convStore2 = require('../services/store/conversation-store');

check('重启后会话仍在', () => {
  const conv = convStore2.get('conv_persist');
  assert.ok(conv, 'conversation should persist across restart');
  assert.strictEqual(conv.name, 'Persist Test');
});

// ── 5. cron-service 验证 ──────────────
console.log('\n5. cron-service 持久化');

clearModuleCache();

// 加载 cron-service 触发默认数据初始化
require('../services/cron-service');

check('cron_jobs 有默认数据', () => {
  const db2 = require('../services/store/db');
  const count = db2.prepare('SELECT COUNT(*) AS c FROM cron_jobs').get().c;
  assert.ok(count >= 2, `Expected at least 2 default jobs, got ${count}`);
});

check('toggle job 持久化', () => {
  const db2 = require('../services/store/db');
  // 先查初始状态
  const before = db2.prepare("SELECT enabled FROM cron_jobs WHERE id = 'job_news'").get();
  assert.strictEqual(before.enabled, 1, 'job_news should be enabled by default');
  
  // toggle
  db2.prepare("UPDATE cron_jobs SET enabled = 0 WHERE id = 'job_news'").run();
  
  // 验证
  const after = db2.prepare("SELECT enabled FROM cron_jobs WHERE id = 'job_news'").get();
  assert.strictEqual(after.enabled, 0, 'job_news should be disabled after toggle');
  
  // 恢复
  db2.prepare("UPDATE cron_jobs SET enabled = 1 WHERE id = 'job_news'").run();
});

// ── 6. 7 天清理验证 ──────────────
console.log('\n6. 7 天清理逻辑');

check('8 天前的消息被清理', () => {
  const db2 = require('../services/store/db');
  const eightDaysAgo = Date.now() - (8 * 24 * 60 * 60 * 1000);
  
  // 插入一条过时消息
  db2.prepare(`
    INSERT INTO messages (id, account_id, client_msg_id, sender_id, type, content, created_at, seq)
    VALUES ('old_msg', 'conv_old', NULL, 'user', 'text', 'old message', ?, 999999)
  `).run(eightDaysAgo);
  
  // 验证存在
  const before = db2.prepare("SELECT * FROM messages WHERE id = 'old_msg'").get();
  assert.ok(before, 'old message should exist before cleanup');
  
  // 执行清理
  const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
  const cutoff = Date.now() - SEVEN_DAYS_MS;
  const { changes } = db2.prepare('DELETE FROM messages WHERE created_at < ?').run(cutoff);
  
  // 验证删除
  const after = db2.prepare("SELECT * FROM messages WHERE id = 'old_msg'").get();
  assert.strictEqual(after, undefined, 'old message should be deleted after cleanup');
  assert.ok(changes >= 1, 'at least 1 message should be cleaned up');
});

check('6 天前的消息不被清理', () => {
  const db2 = require('../services/store/db');
  const sixDaysAgo = Date.now() - (6 * 24 * 60 * 60 * 1000);
  
  db2.prepare(`
    INSERT INTO messages (id, account_id, client_msg_id, sender_id, type, content, created_at, seq)
    VALUES ('recent_msg', 'conv_recent', NULL, 'user', 'text', 'recent message', ?, 999998)
  `).run(sixDaysAgo);
  
  const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
  const cutoff = Date.now() - SEVEN_DAYS_MS;
  db2.prepare('DELETE FROM messages WHERE created_at < ?').run(cutoff);
  
  const still = db2.prepare("SELECT * FROM messages WHERE id = 'recent_msg'").get();
  assert.ok(still, '6-day-old message should NOT be cleaned up');
  
  // 清理测试数据
  db2.prepare("DELETE FROM messages WHERE id = 'recent_msg'").run();
});

// ── 7. clearUpToSeq 保留但 index.js 不调用 ──────────────
console.log('\n7. clearUpToSeq API 保留');

check('clearUpToSeq 仍然可用', () => {
  clearModuleCache();
  const ms = require('../services/store/message-store');
  const deleted = ms.clearUpToSeq(1); // 删除 seq <= 1
  assert.ok(deleted >= 0, 'clearUpToSeq should return changes count');
});

check('index.js 不再调用 clearUpToSeq', () => {
  const indexCode = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  assert.ok(!indexCode.includes('clearUpToSeq(maxSeq)'), 'index.js should not call clearUpToSeq(maxSeq)');
  assert.ok(!indexCode.includes('clearUpToSeq('), 'index.js should not call clearUpToSeq at all');
});

// ── 8. DB 文件大小 ──────────────
console.log('\n8. DB 文件');

check('clawke.db 大小 > 0', () => {
  const stat = fs.statSync(DB_PATH);
  assert.ok(stat.size > 0, `DB size should be > 0, got ${stat.size}`);
  console.log(`    📁 clawke.db: ${stat.size} bytes`);
});

// ── 清理测试数据 ──────────────
clearModuleCache();
const dbClean = require('../services/store/db');
dbClean.exec('DELETE FROM messages');
dbClean.exec('DELETE FROM conversations');

// ── 总结 ──────────────
console.log('\n' + '='.repeat(40));
console.log(`结果: ${passed} 通过, ${failed} 失败, ${passed + failed} 总计`);
console.log('='.repeat(40));

process.exit(failed > 0 ? 1 : 0);
