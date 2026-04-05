import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/providers/ws_state_provider.dart';

/// 数据库单例
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
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
  return ConversationRepository(dao: ref.watch(conversationDaoProvider));
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository(
    messageDao: ref.watch(messageDaoProvider),
    conversationDao: ref.watch(conversationDaoProvider),
    ws: ref.watch(wsServiceProvider),
  );
});
