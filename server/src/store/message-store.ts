/**
 * MessageStore — 消息持久化
 *
 * 构造函数注入 Database 实例。
 * globalSeq 从 DB 恢复，确保永不回退。
 */
import * as crypto from 'crypto';
import { Database } from './database.js';
import type BetterSqlite3 from 'better-sqlite3';

export interface StoreResult {
  serverMsgId: string;
  seq: number;
  ts: number;
}

export interface StoredMessage {
  seq: number;
  serverMsgId: string;
  clientMsgId: string | null;
  accountId: string;
  conversationId: string;
  senderId: string;
  type: string;
  content: string;
  ts: number;
}

export class MessageStore {
  private globalSeq: number;
  private insertStmt: BetterSqlite3.Statement;
  private updateSeqStmt: BetterSqlite3.Statement;
  private getAfterStmt: BetterSqlite3.Statement;
  private deleteUpToStmt: BetterSqlite3.Statement;
  private insertWithMeta: BetterSqlite3.Transaction;

  constructor(private database: Database) {
    const db = database.raw;

    // Prepared statements
    this.insertStmt = db.prepare(`
      INSERT INTO messages (id, account_id, conversation_id, client_msg_id, sender_id, type, content, created_at, seq)
      VALUES (@id, @account_id, @conversation_id, @client_msg_id, @sender_id, @type, @content, @created_at, @seq)
    `);
    this.updateSeqStmt = db.prepare(
      "INSERT OR REPLACE INTO metadata (key, value) VALUES ('globalSeq', ?)"
    );
    this.getAfterStmt = db.prepare(
      'SELECT * FROM messages WHERE seq > ? ORDER BY seq ASC LIMIT 500'
    );
    this.deleteUpToStmt = db.prepare('DELETE FROM messages WHERE seq <= ?');

    // 事务：写消息 + 更新 globalSeq metadata
    this.insertWithMeta = db.transaction((row: Record<string, unknown>) => {
      this.insertStmt.run(row);
      this.updateSeqStmt.run(String(row.seq));
    });

    // 恢复 globalSeq
    this.globalSeq = this.recoverGlobalSeq();
  }

  /** 从 DB 恢复 globalSeq */
  private recoverGlobalSeq(): number {
    const db = this.database.raw;
    const metaRow = db.prepare("SELECT value FROM metadata WHERE key = 'globalSeq'").get() as { value: string } | undefined;
    const maxMsgSeq = (db.prepare('SELECT COALESCE(MAX(seq), 0) AS v FROM messages').get() as { v: number }).v;

    const seq = Math.max(
      metaRow ? parseInt(metaRow.value, 10) : 0,
      maxMsgSeq,
    );

    if (seq > 0) {
      console.log(`[MessageStore] Recovered globalSeq = ${seq} from DB (meta=${metaRow?.value || 0}, maxMsg=${maxMsgSeq})`);
    }
    return seq;
  }

  /** 行映射：DB 列名 → StoredMessage */
  private toMsg(row: Record<string, unknown>): StoredMessage {
    return {
      seq: row.seq as number,
      serverMsgId: row.id as string,
      clientMsgId: row.client_msg_id as string | null,
      accountId: row.account_id as string,
      conversationId: (row.conversation_id as string) || (row.account_id as string),
      senderId: row.sender_id as string,
      type: row.type as string,
      content: row.content as string,
      ts: row.created_at as number,
    };
  }

  /** 追加消息 */
  append(accountId: string, conversationId: string, clientMsgId: string | null, senderId: string, type: string, content: string): StoreResult {
    this.globalSeq++;
    const serverMsgId = `smsg_${crypto.randomUUID().slice(0, 8)}`;
    const ts = Date.now();
    const row = {
      id: serverMsgId,
      account_id: accountId,
      conversation_id: conversationId,
      client_msg_id: clientMsgId || null,
      sender_id: senderId,
      type: type || 'text',
      content: typeof content === 'string' ? content : JSON.stringify(content),
      created_at: ts,
      seq: this.globalSeq,
    };

    try {
      this.insertWithMeta(row);
    } catch (err: unknown) {
      const sqliteErr = err as { code?: string };
      if (sqliteErr.code === 'SQLITE_CONSTRAINT_UNIQUE') {
        if (clientMsgId) {
          const existing = this.database.raw.prepare(
            'SELECT id, seq, created_at FROM messages WHERE client_msg_id = ?'
          ).get(clientMsgId) as { id: string; seq: number; created_at: number } | undefined;
          if (existing) {
            this.globalSeq--;
            console.warn(`[MessageStore] Duplicate upstream msg: client_msg_id=${clientMsgId} → returning existing id=${existing.id}`);
            return { serverMsgId: existing.id, seq: existing.seq, ts: existing.created_at };
          }
        }
        // seq collision — 重新对齐
        const dbMax = (this.database.raw.prepare('SELECT COALESCE(MAX(seq), 0) AS v FROM messages').get() as { v: number }).v;
        console.warn(`[MessageStore] seq collision: in-memory=${this.globalSeq}, dbMax=${dbMax} → re-sync`);
        this.globalSeq = dbMax + 1;
        row.seq = this.globalSeq;
        this.insertWithMeta(row);
      } else {
        throw err;
      }
    }

    return { serverMsgId, seq: this.globalSeq, ts };
  }

  /** 获取 seq 之后的消息 */
  getAfterSeq(lastSeq: number): StoredMessage[] {
    return (this.getAfterStmt.all(lastSeq) as Record<string, unknown>[]).map(r => this.toMsg(r));
  }

  /** 获取当前 globalSeq */
  getCurrentSeq(): number {
    return this.globalSeq;
  }

  /** 清除 seq <= 指定值的消息（7 天 TTL 清理用） */
  clearUpToSeq(seq: number): number {
    return this.deleteUpToStmt.run(seq).changes;
  }

  /**
   * 重置存储（仅用于测试）
   * ⚠️ 不重置 globalSeq — 客户端持久化了 last_seq
   */
  reset(): void {
    this.database.raw.exec('DELETE FROM messages');
  }
}
