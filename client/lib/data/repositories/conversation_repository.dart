import 'package:drift/drift.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';

class ConversationRepository {
  final ConversationDao _dao;

  ConversationRepository({required ConversationDao dao}) : _dao = dao;

  /// 监听所有会话
  Stream<List<Conversation>> watchAll() => _dao.watchAll();

  /// 获取单个会话
  Future<Conversation?> getConversation(String id) => _dao.getConversation(id);

  /// 创建或更新会话
  Future<void> ensureConversation({
    required String accountId,
    required String type,
    String? name,
    String? iconUrl,
  }) {
    return _dao.upsertConversation(
      ConversationsCompanion(
        accountId: Value(accountId),
        type: Value(type),
        name: Value(name),
        iconUrl: Value(iconUrl),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 标记已读
  Future<void> markAsRead(String accountId) {
    return _dao.resetUnseenCount(accountId);
  }

  /// 切换置顶
  Future<void> togglePin(String accountId) async {
    final conv = await _dao.getConversation(accountId);
    if (conv != null) {
      await _dao.updatePin(accountId, conv.isPinned == 0);
    }
  }

  /// 切换免打扰
  Future<void> toggleMute(String accountId) async {
    final conv = await _dao.getConversation(accountId);
    if (conv != null) {
      await _dao.updateMute(accountId, conv.isMuted == 0);
    }
  }

  /// 保存草稿
  Future<void> saveDraft(String accountId, String? draft) {
    return _dao.updateDraft(accountId, draft);
  }

  /// 重命名会话
  Future<void> renameConversation(String accountId, String newName) {
    return _dao.updateName(accountId, newName);
  }

  /// 删除会话
  Future<void> deleteConversation(String accountId) {
    return _dao.deleteConversation(accountId);
  }
}
