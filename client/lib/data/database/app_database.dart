import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

@DriftDatabase(include: {'tables/conversations.drift', 'tables/messages.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 用于测试的构造函数
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

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
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'clawke', 'clawke.db'));

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
