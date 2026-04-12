/**
 * Database — SQLite 持久化层
 *
 * 显式初始化：构造函数接受 dbPath，不在 import 时触发副作用。
 * 清理定时器需手动启动/停止。
 */
import BetterSqlite3 from 'better-sqlite3';

const SCHEMA_VERSION = 3;
const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

export class Database {
  private db: BetterSqlite3.Database;
  private cleanupTimer: ReturnType<typeof setInterval> | null = null;

  constructor(dbPath: string) {
    this.db = new BetterSqlite3(dbPath);
    this.configurePragmas();
    this.runMigrations();
  }

  /** 获取底层 better-sqlite3 实例（供 Store 使用） */
  get raw(): BetterSqlite3.Database {
    return this.db;
  }

  /** 配置 SQLite PRAGMA */
  private configurePragmas(): void {
    this.db.pragma('journal_mode = WAL');
    this.db.pragma('synchronous = NORMAL');
    this.db.pragma('foreign_keys = ON');
    this.db.pragma('busy_timeout = 5000');
  }

  /** Schema 初始化 + 迁移 */
  private runMigrations(): void {
    const currentVersion = this.db.pragma('user_version', { simple: true }) as number;

    if (currentVersion < SCHEMA_VERSION) {
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          client_msg_id TEXT,
          sender_id TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'text',
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          seq INTEGER NOT NULL UNIQUE
        );
        CREATE INDEX IF NOT EXISTS idx_messages_seq ON messages(seq);
        CREATE INDEX IF NOT EXISTS idx_messages_account ON messages(account_id, seq);

        CREATE TABLE IF NOT EXISTS conversations (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL DEFAULT 'dm',
          name TEXT,
          created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS cron_jobs (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          schedule TEXT NOT NULL,
          schedule_text TEXT,
          message TEXT,
          enabled INTEGER NOT NULL DEFAULT 1,
          last_run_time TEXT,
          last_run_success INTEGER
        );

        CREATE TABLE IF NOT EXISTS metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      `);
      this.db.pragma(`user_version = ${SCHEMA_VERSION}`);
      console.log(`[DB] Schema v${SCHEMA_VERSION} initialized`);
    }

    // v2 → v3 迁移
    if (currentVersion < 3) {
      this.db.exec(`
        CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_client_msg_id
          ON messages(client_msg_id) WHERE client_msg_id IS NOT NULL;
      `);
      this.db.pragma('user_version = 3');
      console.log('[DB] Migration v2→v3: added unique index on client_msg_id');
    }

    // v3 → v4 迁移：conversations 表增加 updated_at, is_pinned, is_muted
    try {
      this.db.exec(`ALTER TABLE conversations ADD COLUMN updated_at INTEGER;`);
    } catch { /* 列已存在 */ }
    try {
      this.db.exec(`ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;`);
    } catch { /* 列已存在 */ }
    try {
      this.db.exec(`ALTER TABLE conversations ADD COLUMN is_muted INTEGER NOT NULL DEFAULT 0;`);
    } catch { /* 列已存在 */ }
    try {
      this.db.exec(`ALTER TABLE conversations ADD COLUMN account_id TEXT;`);
    } catch { /* 列已存在 */ }
    // 回填 updated_at（旧数据用 created_at）
    this.db.exec(`UPDATE conversations SET updated_at = created_at WHERE updated_at IS NULL;`);

    // v4 → v5 迁移：messages 表增加 conversation_id（多会话路由）
    try {
      this.db.exec(`ALTER TABLE messages ADD COLUMN conversation_id TEXT;`);
      console.log('[DB] Migration v4→v5: added conversation_id to messages');
    } catch { /* 列已存在 */ }
    // 回填：旧数据 conversation_id = account_id
    this.db.exec(`UPDATE messages SET conversation_id = account_id WHERE conversation_id IS NULL;`);
    this.db.exec(`CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, seq);`);
  }

  /** 立即执行 7 天消息清理 */
  cleanup(): number {
    const cutoff = Date.now() - SEVEN_DAYS_MS;
    const stmt = this.db.prepare('DELETE FROM messages WHERE created_at < ?');
    const { changes } = stmt.run(cutoff);
    if (changes > 0) {
      console.log(`[DB] Cleaned ${changes} messages older than 7 days`);
    }
    return changes;
  }

  /** 启动每日清理定时器 */
  startCleanupScheduler(): void {
    if (this.cleanupTimer) return;
    this.cleanup(); // 启动时立即清理一次
    this.cleanupTimer = setInterval(() => this.cleanup(), ONE_DAY_MS);
    if (this.cleanupTimer.unref) this.cleanupTimer.unref();
  }

  /** 停止清理定时器 */
  stopCleanupScheduler(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }
  }

  /** 关闭数据库连接 */
  close(): void {
    this.stopCleanupScheduler();
    this.db.close();
  }
}
