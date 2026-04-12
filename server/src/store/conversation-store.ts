/**
 * ConversationStore — 会话管理（Server 权威）
 *
 * 所有 CRUD 操作的 source of truth。
 */
import { Database } from './database.js';
import type BetterSqlite3 from 'better-sqlite3';

export interface Conversation {
  id: string;
  type: string;
  name: string | null;
  accountId: string | null;
  isPinned: boolean;
  isMuted: boolean;
  createdAt: number;
  updatedAt: number;
}

export class ConversationStore {
  private findStmt: BetterSqlite3.Statement;
  private insertStmt: BetterSqlite3.Statement;
  private listStmt: BetterSqlite3.Statement;
  private updateStmt: BetterSqlite3.Statement;
  private deleteStmt: BetterSqlite3.Statement;
  private deleteMessagesStmt: BetterSqlite3.Statement;
  private deleteConfigStmt: BetterSqlite3.Statement;
  private touchStmt: BetterSqlite3.Statement;
  private renameStmt: BetterSqlite3.Statement;

  constructor(private database: Database) {
    const db = database.raw;
    this.findStmt = db.prepare('SELECT * FROM conversations WHERE id = ?');
    this.insertStmt = db.prepare(`
      INSERT OR IGNORE INTO conversations (id, type, name, account_id, is_pinned, is_muted, created_at, updated_at)
      VALUES (@id, @type, @name, @account_id, @is_pinned, @is_muted, @created_at, @updated_at)
    `);
    this.listStmt = db.prepare(
      'SELECT * FROM conversations ORDER BY is_pinned DESC, updated_at DESC'
    );
    this.updateStmt = db.prepare(`
      UPDATE conversations
      SET name = COALESCE(@name, name),
          is_pinned = COALESCE(@is_pinned, is_pinned),
          is_muted = COALESCE(@is_muted, is_muted),
          updated_at = @updated_at
      WHERE id = @id
    `);
    this.deleteStmt = db.prepare('DELETE FROM conversations WHERE id = ?');
    this.deleteMessagesStmt = db.prepare(
      'DELETE FROM messages WHERE conversation_id = ?'
    );
    this.deleteConfigStmt = db.prepare(
      'DELETE FROM conversation_configs WHERE conv_id = ?'
    );
    this.touchStmt = db.prepare(
      'UPDATE conversations SET updated_at = @updated_at WHERE id = @id'
    );
    this.renameStmt = db.prepare(
      'UPDATE conversations SET name = @name WHERE id = @id'
    );
  }

  /** 行映射 */
  private toConv(row: Record<string, unknown> | undefined): Conversation | null {
    if (!row) return null;
    return {
      id: row.id as string,
      type: row.type as string,
      name: row.name as string | null,
      accountId: row.account_id as string | null,
      isPinned: (row.is_pinned as number) === 1,
      isMuted: (row.is_muted as number) === 1,
      createdAt: row.created_at as number,
      updatedAt: (row.updated_at as number) ?? (row.created_at as number),
    };
  }

  /** 确保会话存在（不存在则创建） */
  ensure(convId: string, type: string = 'dm', name: string | null = null, accountId: string | null = null): Conversation {
    const existing = this.findStmt.get(convId) as Record<string, unknown> | undefined;
    if (existing) {
      return this.toConv(existing)!;
    }
    const now = Date.now();
    this.insertStmt.run({
      id: convId,
      type,
      name: name || convId,
      account_id: accountId,
      is_pinned: 0,
      is_muted: 0,
      created_at: now,
      updated_at: now,
    });
    return this.toConv(this.findStmt.get(convId) as Record<string, unknown>)!;
  }

  /** 创建新会话 */
  create(convId: string, type: string = 'dm', name: string | null = null, accountId: string | null = null): Conversation {
    return this.ensure(convId, type, name, accountId);
  }

  /** 获取会话 */
  get(convId: string): Conversation | null {
    return this.toConv(this.findStmt.get(convId) as Record<string, unknown> | undefined);
  }

  /** 列出所有会话（置顶优先，最新消息倒序） */
  list(): Conversation[] {
    return (this.listStmt.all() as Record<string, unknown>[]).map(r => this.toConv(r)!);
  }

  /** 更新会话属性（name, isPinned, isMuted） */
  update(convId: string, fields: { name?: string; isPinned?: boolean; isMuted?: boolean }): void {
    this.updateStmt.run({
      id: convId,
      name: fields.name ?? null,
      is_pinned: fields.isPinned !== undefined ? (fields.isPinned ? 1 : 0) : null,
      is_muted: fields.isMuted !== undefined ? (fields.isMuted ? 1 : 0) : null,
      updated_at: Date.now(),
    });
  }

  /** 重命名会话 */
  rename(convId: string, name: string): void {
    this.renameStmt.run({ id: convId, name });
  }

  /** 更新 updated_at（消息到达时调用） */
  touch(convId: string): void {
    this.touchStmt.run({ id: convId, updated_at: Date.now() });
  }

  /** 删除会话（级联删除 messages + configs） */
  delete(convId: string): void {
    this.deleteConfigStmt.run(convId);
    // messages 通过 conversation_id 精确关联
    try {
      this.database.raw.prepare(
        'DELETE FROM messages WHERE conversation_id = ?'
      ).run(convId);
    } catch (e) {
      console.warn(`[ConvStore] Failed to delete messages for ${convId}:`, e);
    }
    this.deleteStmt.run(convId);
    console.log(`[ConvStore] Deleted conversation ${convId} (with messages & config)`);
  }

  /** 重置（仅用于测试） */
  reset(): void {
    this.database.raw.exec('DELETE FROM conversations');
  }
}
