import 'package:drift/drift.dart';
import 'package:client/data/database/app_database.dart';

class ConversationDao {
  final AppDatabase _db;
  ConversationDao(this._db);

  /// 监听所有会话（置顶优先，最新消息排前）
  Stream<List<Conversation>> watchAll() {
    return _db.watchAllConversations().watch();
  }

  /// 获取单个会话
  Future<Conversation?> getConversation(String id) {
    return _db.getConversation(id).getSingleOrNull();
  }

  /// 插入或更新会话
  Future<void> upsertConversation(ConversationsCompanion entry) {
    return _db.into(_db.conversations).insertOnConflictUpdate(entry);
  }

  /// 更新最后一条消息信息
  Future<void> updateLastMessage({
    required String accountId,
    required String messageId,
    required int messageAt,
    required String preview,
  }) {
    return (_db.update(
      _db.conversations,
    )..where((t) => t.accountId.equals(accountId))).write(
      ConversationsCompanion(
        lastMessageId: Value(messageId),
        lastMessageAt: Value(messageAt),
        lastMessagePreview: Value(preview),
      ),
    );
  }

  /// 未读计数 +1
  Future<void> incrementUnseenCount(String accountId) {
    return _db.customStatement(
      'UPDATE conversations SET unseen_count = unseen_count + 1 WHERE account_id = ?',
      [accountId],
    );
  }

  /// 清零未读
  Future<void> resetUnseenCount(String accountId) {
    return (_db.update(_db.conversations)
          ..where((t) => t.accountId.equals(accountId)))
        .write(const ConversationsCompanion(unseenCount: Value(0)));
  }

  /// 切换置顶
  Future<void> updatePin(String accountId, bool isPinned) {
    return (_db.update(_db.conversations)
          ..where((t) => t.accountId.equals(accountId)))
        .write(ConversationsCompanion(isPinned: Value(isPinned ? 1 : 0)));
  }

  /// 切换免打扰
  Future<void> updateMute(String accountId, bool isMuted) {
    return (_db.update(_db.conversations)
          ..where((t) => t.accountId.equals(accountId)))
        .write(ConversationsCompanion(isMuted: Value(isMuted ? 1 : 0)));
  }

  /// 更新会话名称
  Future<void> updateName(String accountId, String name) {
    return (_db.update(_db.conversations)
          ..where((t) => t.accountId.equals(accountId)))
        .write(ConversationsCompanion(name: Value(name)));
  }

  /// 保存草稿
  Future<void> updateDraft(String accountId, String? draft) {
    return (_db.update(_db.conversations)
          ..where((t) => t.accountId.equals(accountId)))
        .write(ConversationsCompanion(draft: Value(draft)));
  }

  /// 删除会话
  Future<void> deleteConversation(String accountId) {
    return (_db.delete(
      _db.conversations,
    )..where((t) => t.accountId.equals(accountId))).go();
  }
}
