import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:client/data/database/app_database.dart';

class MessageDao {
  final AppDatabase _db;
  MessageDao(this._db);

  /// 监听某个会话的消息（按时间倒序，限制条数）
  Stream<List<Message>> watchMessages(String conversationId, {int limit = 50}) {
    return _db.watchMessagesInConversation(conversationId, limit).watch();
  }

  /// 获取单条消息
  Future<Message?> getMessage(String messageId) {
    return _db.getMessageById(messageId).getSingleOrNull();
  }

  /// 插入消息
  Future<void> insertMessage(MessagesCompanion entry) {
    return _db.into(_db.messages).insertOnConflictUpdate(entry);
  }

  /// 更新消息状态
  Future<void> updateStatus(
    String messageId,
    String status, {
    String? serverId,
    int? seq,
  }) {
    final companion = MessagesCompanion(
      status: Value(status),
      serverId: Value(serverId),
      seq: Value(seq ?? 0),
    );
    return (_db.update(
      _db.messages,
    )..where((t) => t.messageId.equals(messageId))).write(companion);
  }

  /// 更新消息内容（编辑）
  Future<void> updateContent(String messageId, String newContent) {
    return (_db.update(
      _db.messages,
    )..where((t) => t.messageId.equals(messageId))).write(
      MessagesCompanion(
        content: Value(newContent),
        editedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 软删除消息
  Future<void> softDelete(String messageId) {
    return (_db.update(_db.messages)
          ..where((t) => t.messageId.equals(messageId)))
        .write(const MessagesCompanion(status: Value('deleted')));
  }

  /// 更新消息的 token 用量
  Future<void> updateTokenUsage(
    String messageId, {
    required int inputTokens,
    required int outputTokens,
    String? modelName,
  }) {
    return (_db.update(
      _db.messages,
    )..where((t) => t.messageId.equals(messageId))).write(
      MessagesCompanion(
        inputTokens: Value(inputTokens),
        outputTokens: Value(outputTokens),
        modelName: Value(modelName),
      ),
    );
  }

  /// 删除某个会话中的所有消息
  Future<void> deleteByConversation(String conversationId) {
    return (_db.delete(
      _db.messages,
    )..where((t) => t.conversationId.equals(conversationId))).go();
  }

  /// 获取所有 sending 状态的消息（重连后重试用）
  Future<List<Message>> getPendingMessages() {
    return _db.getMessagesByStatus('sending').get();
  }

  /// 获取本地最大 seq（用于增量同步）
  Future<int> getMaxSeq() async {
    final result = await _db.getMaxSeq().getSingleOrNull();
    return result ?? 0;
  }

  /// 设置 seq 基线（新设备首次 sync 时，服务端返回 current_seq 但不返回消息）
  /// 插入一条不可见的标记消息，确保 getMaxSeq 能返回正确的基线值
  Future<void> setSeqBaseline(int seq) async {
    if (seq <= 0) return;
    final current = await getMaxSeq();
    if (current >= seq) return; // 已有更高的 seq，不需要设定基线
    // 使用 default 会话以满足外键约束
    // status='baseline' 确保不会出现在聊天列表中
    await insertMessage(MessagesCompanion(
      messageId: Value('_seq_baseline_$seq'),
      accountId: const Value('default'),
      conversationId: const Value('default'),
      senderId: const Value('system'),
      type: const Value('system'),
      content: const Value(''),
      status: const Value('baseline'),
      seq: Value(seq),
      createdAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// 替换包含指定模式的消息内容（用于 Clarify/Approval 卡片持久化）
  ///
  /// 查找包含 [pattern] 的最近一条消息，将 [pattern] 替换为 [replacement]
  Future<void> replaceContentPattern(String pattern, String replacement) async {
    debugPrint('[MessageDao] replaceContentPattern: pattern(${pattern.length})');
    final allMsgs = await (_db.select(_db.messages)
      ..where((t) => t.content.contains(pattern))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1))
      .get();
    if (allMsgs.isEmpty) {
      debugPrint('[MessageDao] replaceContentPattern: no matching message found');
      return;
    }
    final msg = allMsgs.first;
    final newContent = msg.content?.replaceAll(pattern, replacement);
    if (newContent != null) {
      debugPrint('[MessageDao] replaceContentPattern: updated msgId=${msg.messageId}');
      // 不设 editedAt：卡片交互替换不算"用户编辑"
      await (_db.update(_db.messages)
        ..where((t) => t.messageId.equals(msg.messageId)))
        .write(MessagesCompanion(content: Value(newContent)));
    }
  }
}
