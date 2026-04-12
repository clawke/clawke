/**
 * ConversationConfigStore — 会话级配置存储
 *
 * 存储每个会话的模型、skill、系统提示词等配置。
 * 使用独立的 SQLite 表 conversation_configs。
 */
import type { Database } from './database.js';
import type BetterSqlite3 from 'better-sqlite3';

export interface ConversationConfig {
  convId: string;
  accountId: string;
  modelId: string | null;
  skills: string | null;       // JSON array: '["camsnap","github"]'
  skillMode: string | null;    // 'priority' | 'exclusive'
  systemPrompt: string | null;
  workDir: string | null;      // 会话级工作目录
  updatedAt: number;
}

export class ConversationConfigStore {
  private getStmt: BetterSqlite3.Statement;
  private upsertStmt: BetterSqlite3.Statement;
  private deleteStmt: BetterSqlite3.Statement;

  constructor(database: Database) {
    const db = database.raw;

    // 建表
    db.exec(`
      CREATE TABLE IF NOT EXISTS conversation_configs (
        conv_id       TEXT PRIMARY KEY,
        account_id    TEXT NOT NULL,
        model_id      TEXT,
        skills        TEXT,
        skill_mode    TEXT,
        system_prompt TEXT,
        work_dir      TEXT,
        updated_at    INTEGER NOT NULL
      );
    `);

    // 兼容旧数据库：如果 work_dir 列不存在则添加
    try {
      db.exec(`ALTER TABLE conversation_configs ADD COLUMN work_dir TEXT;`);
    } catch {
      // 列已存在，忽略
    }

    this.getStmt = db.prepare('SELECT * FROM conversation_configs WHERE conv_id = ?');
    this.upsertStmt = db.prepare(`
      INSERT INTO conversation_configs (conv_id, account_id, model_id, skills, skill_mode, system_prompt, work_dir, updated_at)
      VALUES (@conv_id, @account_id, @model_id, @skills, @skill_mode, @system_prompt, @work_dir, @updated_at)
      ON CONFLICT(conv_id) DO UPDATE SET
        account_id = @account_id,
        model_id = @model_id,
        skills = @skills,
        skill_mode = @skill_mode,
        system_prompt = @system_prompt,
        work_dir = @work_dir,
        updated_at = @updated_at
    `);
    this.deleteStmt = db.prepare('DELETE FROM conversation_configs WHERE conv_id = ?');
  }

  /** 行映射 */
  private toConfig(row: Record<string, unknown> | undefined): ConversationConfig | null {
    if (!row) return null;
    return {
      convId: row.conv_id as string,
      accountId: row.account_id as string,
      modelId: row.model_id as string | null,
      skills: row.skills as string | null,
      skillMode: row.skill_mode as string | null,
      systemPrompt: row.system_prompt as string | null,
      workDir: row.work_dir as string | null,
      updatedAt: row.updated_at as number,
    };
  }

  /** 获取会话配置 */
  get(convId: string): ConversationConfig | null {
    return this.toConfig(this.getStmt.get(convId) as Record<string, unknown> | undefined);
  }

  /** 保存/更新会话配置 */
  set(convId: string, accountId: string, config: {
    modelId?: string | null;
    skills?: string | null;
    skillMode?: string | null;
    systemPrompt?: string | null;
    workDir?: string | null;
  }): void {
    this.upsertStmt.run({
      conv_id: convId,
      account_id: accountId,
      model_id: config.modelId ?? null,
      skills: config.skills ?? null,
      skill_mode: config.skillMode ?? null,
      system_prompt: config.systemPrompt ?? null,
      work_dir: config.workDir ?? null,
      updated_at: Date.now(),
    });
  }

  /** 删除会话配置 */
  delete(convId: string): void {
    this.deleteStmt.run(convId);
  }
}
