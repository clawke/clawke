import 'package:drift/drift.dart';
import 'package:client/data/database/app_database.dart';

class ConversationDao {
  final AppDatabase _db;
  ConversationDao(this._db);

  /// 监听所有会话（置顶优先，最新消息排前）
  Stream<List<Conversation>> watchAll() {
    return _db.watchAllConversations().watch();
  }

  /// 获取所有会话（非 Stream，用于同步对比）
  Future<List<Conversation>> getAllConversations() {
    return _db.watchAllConversations().get();
  }

  /// 获取单个会话（按 conversation_id）
  Future<Conversation?> getConversation(String conversationId) {
    return _db.getConversation(conversationId).getSingleOrNull();
  }

  /// 获取某个 AI 后端下的所有会话
  Future<List<Conversation>> getConversationsByAccount(String accountId) {
    return _db.getConversationsByAccount(accountId).get();
  }

  /// 插入或更新会话
  Future<void> upsertConversation(ConversationsCompanion entry) {
    return _db.into(_db.conversations).insertOnConflictUpdate(entry);
  }

  /// 更新最后一条消息信息
  Future<void> updateLastMessage({
    required String conversationId,
    required String messageId,
    required int messageAt,
    required String preview,
  }) {
    return (_db.update(
      _db.conversations,
    )..where((t) => t.conversationId.equals(conversationId))).write(
      ConversationsCompanion(
        lastMessageId: Value(messageId),
        lastMessageAt: Value(messageAt),
        lastMessagePreview: Value(preview),
      ),
    );
  }

  /// 未读计数 +1
  Future<void> incrementUnseenCount(String conversationId) {
    return _db.customStatement(
      'UPDATE conversations SET unseen_count = unseen_count + 1 WHERE conversation_id = ?',
      [conversationId],
    );
  }

  /// 清零未读
  Future<void> resetUnseenCount(String conversationId) {
    return (_db.update(_db.conversations)
          ..where((t) => t.conversationId.equals(conversationId)))
        .write(const ConversationsCompanion(unseenCount: Value(0)));
  }

  /// 切换置顶
  Future<void> updatePin(String conversationId, bool isPinned) {
    return (_db.update(_db.conversations)
          ..where((t) => t.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(isPinned: Value(isPinned ? 1 : 0)));
  }

  /// 切换免打扰
  Future<void> updateMute(String conversationId, bool isMuted) {
    return (_db.update(_db.conversations)
          ..where((t) => t.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(isMuted: Value(isMuted ? 1 : 0)));
  }

  /// 获取会话名称
  Future<String?> getName(String conversationId) async {
    final conv = await getConversation(conversationId);
    return conv?.name;
  }

  /// 更新会话名称
  Future<void> updateName(String conversationId, String name) {
    return (_db.update(_db.conversations)
          ..where((t) => t.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(name: Value(name)));
  }

  /// 保存草稿
  Future<void> updateDraft(String conversationId, String? draft) {
    return (_db.update(_db.conversations)
          ..where((t) => t.conversationId.equals(conversationId)))
        .write(ConversationsCompanion(draft: Value(draft)));
  }

  /// 删除会话
  Future<void> deleteConversation(String conversationId) {
    return (_db.delete(
      _db.conversations,
    )..where((t) => t.conversationId.equals(conversationId))).go();
  }
}
