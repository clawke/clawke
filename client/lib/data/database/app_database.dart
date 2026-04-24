import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

@DriftDatabase(include: {'tables/conversations.drift', 'tables/messages.drift', 'tables/metadata.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(String uid) : super(_openConnection(uid)) {
    // 多账号切换时会短暂共存两个 DB 实例（指向不同文件），
    // Drift 误报为同 QueryExecutor 竞态，实际无风险，关闭此警告。
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  /// 用于测试的构造函数
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  /// 获取 metadata 值
  Future<String?> getMetadata(String key) async {
    final row = await (select(metadata)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 设置 metadata 值
  Future<void> setMetadata(String key, String value) {
    return into(metadata).insertOnConflictUpdate(
      MetadataCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // 不再硬编码默认会话，会话由 OpenClaw 连接自动创建
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.database.customStatement(
          'ALTER TABLE messages ADD COLUMN thinking_content TEXT',
        );
      }
      if (from < 3) {
        await m.database.customStatement(
          'ALTER TABLE messages ADD COLUMN input_tokens INTEGER',
        );
        await m.database.customStatement(
          'ALTER TABLE messages ADD COLUMN output_tokens INTEGER',
        );
        await m.database.customStatement(
          'ALTER TABLE messages ADD COLUMN model_name TEXT',
        );
      }
      if (from < 4) {
        // conversation_id → account_id 列重命名
        // SQLite 3.25+ 支持 ALTER TABLE RENAME COLUMN
        await m.database.customStatement(
          'ALTER TABLE conversations RENAME COLUMN conversation_id TO account_id',
        );
        await m.database.customStatement(
          'ALTER TABLE messages RENAME COLUMN conversation_id TO account_id',
        );
        // 重建索引
        await m.database.customStatement(
          'DROP INDEX IF EXISTS idx_msg_conv_created',
        );
        await m.database.customStatement(
          'CREATE INDEX idx_msg_acct_created ON messages(account_id, created_at DESC)',
        );
      }
      if (from < 5) {
        // Multi-Session: conversations 表改为 conversation_id 作为 PK
        // SQLite 不支持修改 PK，需要重建表
        await m.database.customStatement('''
          CREATE TABLE conversations_new (
            conversation_id      TEXT    NOT NULL PRIMARY KEY,
            account_id           TEXT    NOT NULL,
            type                 TEXT    NOT NULL DEFAULT 'dm',
            name                 TEXT,
            icon_url             TEXT,
            last_message_id      TEXT,
            last_message_at      INTEGER,
            last_message_preview TEXT,
            draft                TEXT,
            is_pinned            INTEGER NOT NULL DEFAULT 0,
            is_muted             INTEGER NOT NULL DEFAULT 0,
            unseen_count         INTEGER NOT NULL DEFAULT 0,
            created_at           INTEGER NOT NULL
          )
        ''');
        // 迁移数据：旧 account_id 作为 conversation_id（保持兼容）
        await m.database.customStatement('''
          INSERT INTO conversations_new
            (conversation_id, account_id, type, name, icon_url,
             last_message_id, last_message_at, last_message_preview,
             draft, is_pinned, is_muted, unseen_count, created_at)
          SELECT account_id, account_id, type, name, icon_url,
                 last_message_id, last_message_at, last_message_preview,
                 draft, is_pinned, is_muted, unseen_count, created_at
          FROM conversations
        ''');
        await m.database.customStatement('DROP TABLE conversations');
        await m.database.customStatement(
          'ALTER TABLE conversations_new RENAME TO conversations',
        );

        // messages 表也需要重建：FK 从 account_id → conversation_id
        // SQLite 不支持 ALTER FOREIGN KEY，必须用 create-copy-drop-rename
        await m.database.customStatement('DROP INDEX IF EXISTS idx_msg_acct_created');
        await m.database.customStatement('''
          CREATE TABLE messages_new (
            message_id       TEXT    NOT NULL PRIMARY KEY,
            server_id        TEXT,
            account_id       TEXT    NOT NULL,
            conversation_id  TEXT    NOT NULL DEFAULT 'default',
            sender_id        TEXT    NOT NULL,
            type             TEXT    NOT NULL,
            content          TEXT,
            thinking_content TEXT,
            quote_id         TEXT,
            status           TEXT    NOT NULL DEFAULT 'sending',
            seq              INTEGER DEFAULT 0,
            edited_at        INTEGER,
            created_at       INTEGER NOT NULL,
            input_tokens     INTEGER,
            output_tokens    INTEGER,
            model_name       TEXT,
            FOREIGN KEY(conversation_id) REFERENCES conversations(conversation_id)
                ON DELETE CASCADE
          )
        ''');
        await m.database.customStatement('''
          INSERT INTO messages_new
            (message_id, server_id, account_id, conversation_id, sender_id,
             type, content, thinking_content, quote_id, status, seq,
             edited_at, created_at, input_tokens, output_tokens, model_name)
          SELECT message_id, server_id, account_id, account_id, sender_id,
                 type, content, thinking_content, quote_id, status, seq,
                 edited_at, created_at, input_tokens, output_tokens, model_name
          FROM messages
        ''');
        await m.database.customStatement('DROP TABLE messages');
        await m.database.customStatement(
          'ALTER TABLE messages_new RENAME TO messages',
        );
        await m.database.customStatement(
          'CREATE INDEX idx_msg_conv_created ON messages(conversation_id, created_at DESC)',
        );
      }
      if (from < 6) {
        // v6: conversationId 全面改为 UUID，清除旧数据
        await m.database.customStatement('DELETE FROM messages');
        await m.database.customStatement('DELETE FROM conversations');
      }
      if (from < 7) {
        // v7: metadata key-value 表
        await m.database.customStatement('''
          CREATE TABLE IF NOT EXISTS metadata (
            key   TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      }
    },
  );
}

LazyDatabase _openConnection(String uid) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'clawke', 'clawke_$uid.db'));

    // 确保目录存在
    await file.parent.create(recursive: true);

    return NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // 启用 WAL 模式
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('PRAGMA foreign_keys=ON');
      },
    );
  });
}
