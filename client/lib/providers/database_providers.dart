import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/services/config_api_service.dart';

/// 数据库实例 — 按 user/server 隔离
///
/// uid 变化时（登录/登出/切换用户）自动关闭旧 DB、打开新 DB。
final databaseProvider = Provider<AppDatabase>((ref) {
  final uid = ref.watch(currentUserUidProvider);
  debugPrint('[DB] 📀 databaseProvider rebuilt: uid=$uid');
  final db = AppDatabase(uid);
  ref.onDispose(() {
    debugPrint('[DB] 📀 databaseProvider disposing: uid=$uid');
    db.close();
  });
  return db;
});

/// ConfigApiService 单例
final configApiServiceProvider = Provider<ConfigApiService>((ref) {
  return ConfigApiService();
});

/// DAO Providers
final conversationDaoProvider = Provider<ConversationDao>((ref) {
  return ConversationDao(ref.watch(databaseProvider));
});

final messageDaoProvider = Provider<MessageDao>((ref) {
  return MessageDao(ref.watch(databaseProvider));
});

/// Repository Providers
final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  return ConversationRepository(
    dao: ref.watch(conversationDaoProvider),
    api: ref.watch(configApiServiceProvider),
  );
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(
    messageDao: ref.watch(messageDaoProvider),
    conversationDao: ref.watch(conversationDaoProvider),
    ws: ref.watch(wsServiceProvider),
  );
});
