/**
 * ConversationStore — 会话管理
 *
 * 构造函数注入 Database 实例。
 */
import { Database } from './database.js';
import type BetterSqlite3 from 'better-sqlite3';

export interface Conversation {
  id: string;
  type: string;
  name: string | null;
  createdAt: number;
}

export class ConversationStore {
  private findStmt: BetterSqlite3.Statement;
  private insertStmt: BetterSqlite3.Statement;
  private listStmt: BetterSqlite3.Statement;

  constructor(private database: Database) {
    const db = database.raw;
    this.findStmt = db.prepare('SELECT * FROM conversations WHERE id = ?');
    this.insertStmt = db.prepare(`
      INSERT OR IGNORE INTO conversations (id, type, name, created_at)
      VALUES (@id, @type, @name, @created_at)
    `);
    this.listStmt = db.prepare('SELECT * FROM conversations ORDER BY created_at DESC');
  }

  /** 行映射 */
  private toConv(row: Record<string, unknown> | undefined): Conversation | null {
    if (!row) return null;
    return {
      id: row.id as string,
      type: row.type as string,
      name: row.name as string | null,
      createdAt: row.created_at as number,
    };
  }

  /** 确保会话存在（不存在则创建） */
  ensure(convId: string, type: string = 'dm', name: string | null = null): Conversation {
    const existing = this.findStmt.get(convId) as Record<string, unknown> | undefined;
    if (existing) {
      return this.toConv(existing)!;
    }
    this.insertStmt.run({
      id: convId,
      type,
      name: name || convId,
      created_at: Date.now(),
    });
    return this.toConv(this.findStmt.get(convId) as Record<string, unknown>)!;
  }

  /** 获取会话 */
  get(convId: string): Conversation | null {
    return this.toConv(this.findStmt.get(convId) as Record<string, unknown> | undefined);
  }

  /** 列出所有会话 */
  list(): Conversation[] {
    return (this.listStmt.all() as Record<string, unknown>[]).map(r => this.toConv(r)!);
  }

  /** 重置（仅用于测试） */
  reset(): void {
    this.database.raw.exec('DELETE FROM conversations');
  }
}
