import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/services/config_api_service.dart';

const _uuid = Uuid();

class ConversationRepository {
  final ConversationDao _dao;
  final ConfigApiService _api;

  ConversationRepository({
    required ConversationDao dao,
    required ConfigApiService api,
  })  : _dao = dao,
        _api = api;

  /// 监听所有会话
  Stream<List<Conversation>> watchAll() => _dao.watchAll();

  /// 获取单个会话
  Future<Conversation?> getConversation(String conversationId) =>
      _dao.getConversation(conversationId);

  /// 获取某个 accountId 的所有会话
  Future<List<Conversation>> getConversationsByAccount(String accountId) =>
      _dao.getConversationsByAccount(accountId);

  /// 创建新会话（Server 优先 → 成功后写本地）
  Future<String> createConversation({
    required String accountId,
    required String type,
    String? conversationId,
    String? name,
    String? iconUrl,
  }) async {
    final id = conversationId ?? _uuid.v4();

    // 先调 Server API
    final serverConv = await _api.createConversation(
      id: id,
      name: name,
      type: type,
      accountId: accountId,
    );

    // 无论 Server 是否成功，都写本地（保证离线可用）
    final convId = serverConv?.id ?? id;
    await _dao.upsertConversation(
      ConversationsCompanion(
        conversationId: Value(convId),
        accountId: Value(accountId),
        type: Value(type),
        name: Value(name),
        iconUrl: Value(iconUrl),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return convId;
  }

  /// 确保某个 accountId 至少有一个会话存在（系统自动创建）
  /// 如果已存在则不覆盖 name 和 iconUrl
  Future<void> ensureConversation({
    required String accountId,
    required String type,
    String? name,
    String? iconUrl,
  }) async {
    // 检查该 accountId 是否已有会话
    final existing = await _dao.getConversationsByAccount(accountId);
    if (existing.isNotEmpty) return;

    // 新建：始终使用 UUID 作为 conversation_id
    final convId = _uuid.v4();
    // Server 创建
    await _api.createConversation(id: convId, name: name, type: type, accountId: accountId);
    // 本地创建
    return _dao.upsertConversation(
      ConversationsCompanion(
        conversationId: Value(convId),
        accountId: Value(accountId),
        type: Value(type),
        name: Value(name),
        iconUrl: Value(iconUrl),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 标记已读
  Future<void> markAsRead(String conversationId) {
    return _dao.resetUnseenCount(conversationId);
  }

  /// 切换置顶（Server 优先）
  Future<void> togglePin(String conversationId) async {
    final conv = await _dao.getConversation(conversationId);
    if (conv != null) {
      final newPinned = conv.isPinned == 0;
      final ok = await _api.updateConversation(conversationId, isPinned: newPinned);
      if (ok) {
        await _dao.updatePin(conversationId, newPinned);
      }
    }
  }

  /// 切换免打扰（Server 优先）
  Future<void> toggleMute(String conversationId) async {
    final conv = await _dao.getConversation(conversationId);
    if (conv != null) {
      final newMuted = conv.isMuted == 0;
      final ok = await _api.updateConversation(conversationId, isMuted: newMuted);
      if (ok) {
        await _dao.updateMute(conversationId, newMuted);
      }
    }
  }

  /// 保存草稿
  Future<void> saveDraft(String conversationId, String? draft) {
    return _dao.updateDraft(conversationId, draft);
  }

  /// 获取会话名称
  Future<String?> getConversationName(String conversationId) {
    return _dao.getName(conversationId);
  }

  /// 重命名会话（Server 优先）
  Future<void> renameConversation(String conversationId, String newName) async {
    final ok = await _api.updateConversation(conversationId, name: newName);
    if (ok) {
      await _dao.updateName(conversationId, newName);
    }
  }

  /// 删除会话（Server 优先 → 成功后删本地）
  Future<void> deleteConversation(String conversationId) async {
    final ok = await _api.deleteConversation(conversationId);
    if (ok) {
      await _dao.deleteConversation(conversationId);
    } else {
      // Server 失败时仍删本地（可能 Server 上已不存在）
      debugPrint('[ConvRepo] Server delete failed, deleting local anyway');
      await _dao.deleteConversation(conversationId);
    }
  }

  /// 从 Server 同步会话列表（连接时调用）
  ///
  /// 全量对比：增/删/改名/pin/mute，以 Server 为准。
  Future<void> syncFromServer() async {
    try {
      final serverList = await _api.getConversations();
      if (serverList.isEmpty) {
        debugPrint('[ConvRepo] syncFromServer: server returned empty list, skipping');
        return;
      }

      final serverIds = <String>{};
      for (final sc in serverList) {
        serverIds.add(sc.id);
      }

      // 获取本地所有会话
      final localList = await _dao.getAllConversations();
      final localMap = <String, Conversation>{};
      for (final lc in localList) {
        localMap[lc.conversationId] = lc;
      }

      // Server 有、本地没有 → 新建
      for (final sc in serverList) {
        final local = localMap[sc.id];
        if (local == null) {
          // 本地不存在，创建（accountId 优先用 server 返回值）
          await _dao.upsertConversation(
            ConversationsCompanion(
              conversationId: Value(sc.id),
              accountId: Value(sc.accountId ?? sc.id),
              type: Value(sc.type),
              name: Value(sc.name),
              isPinned: Value(sc.isPinned ? 1 : 0),
              isMuted: Value(sc.isMuted ? 1 : 0),
              createdAt: Value(sc.createdAt),
            ),
          );
          debugPrint('[ConvRepo] sync: created ${sc.id} (${sc.name}, account=${sc.accountId})');
        } else {
          // 两边都有 → 检查是否需要更新（name, pin, mute, accountId）
          bool needUpdate = false;
          if (local.name != sc.name) needUpdate = true;
          if ((local.isPinned == 1) != sc.isPinned) needUpdate = true;
          if ((local.isMuted == 1) != sc.isMuted) needUpdate = true;
          // accountId 以 Server 为准（修复旧会话路由错误）
          final serverAccountId = sc.accountId;
          if (serverAccountId != null && local.accountId != serverAccountId) {
            needUpdate = true;
          }

          if (needUpdate) {
            await _dao.upsertConversation(
              ConversationsCompanion(
                conversationId: Value(sc.id),
                accountId: Value(serverAccountId ?? local.accountId),
                type: Value(sc.type),
                name: Value(sc.name),
                isPinned: Value(sc.isPinned ? 1 : 0),
                isMuted: Value(sc.isMuted ? 1 : 0),
                createdAt: Value(sc.createdAt),
              ),
            );
            debugPrint('[ConvRepo] sync: updated ${sc.id} (name=${sc.name}, pin=${sc.isPinned}, mute=${sc.isMuted}, account=${serverAccountId ?? local.accountId})');
          }
        }
      }

      // 本地有、Server 没有 → 删除
      for (final lc in localList) {
        if (!serverIds.contains(lc.conversationId)) {
          await _dao.deleteConversation(lc.conversationId);
          debugPrint('[ConvRepo] sync: deleted ${lc.conversationId} (not on server)');
        }
      }

      debugPrint('[ConvRepo] syncFromServer done: ${serverList.length} server, ${localList.length} local');
    } catch (e) {
      debugPrint('[ConvRepo] syncFromServer error: $e');
    }
  }
}
