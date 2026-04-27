import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/gateway_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/data/database/dao/skill_cache_dao.dart';
import 'package:client/data/database/dao/task_cache_dao.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/model_cache_repository.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/services/config_api_service.dart';
import 'package:client/services/gateways_api_service.dart';
import 'package:client/services/models_api_service.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:client/services/tasks_api_service.dart';

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

final gatewaysApiServiceProvider = Provider<GatewaysApiService>((ref) {
  return GatewaysApiService();
});

final tasksApiServiceProvider = Provider<TasksApiService>((ref) {
  return TasksApiService();
});

final modelsApiServiceProvider = Provider<ModelsApiService>((ref) {
  return ModelsApiService();
});

final skillsApiServiceProvider = Provider<SkillsApiService>((ref) {
  return SkillsApiService();
});

/// DAO Providers
final conversationDaoProvider = Provider<ConversationDao>((ref) {
  return ConversationDao(ref.watch(databaseProvider));
});

final messageDaoProvider = Provider<MessageDao>((ref) {
  return MessageDao(ref.watch(databaseProvider));
});

final gatewayDaoProvider = Provider<GatewayDao>((ref) {
  return GatewayDao(ref.watch(databaseProvider));
});

final taskCacheDaoProvider = Provider<TaskCacheDao>((ref) {
  return TaskCacheDao(ref.watch(databaseProvider));
});

final modelCacheDaoProvider = Provider<ModelCacheDao>((ref) {
  return ModelCacheDao(ref.watch(databaseProvider));
});

final skillCacheDaoProvider = Provider<SkillCacheDao>((ref) {
  return SkillCacheDao(ref.watch(databaseProvider));
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

final gatewayRepositoryProvider = Provider<GatewayRepository>((ref) {
  return GatewayRepository(
    dao: ref.watch(gatewayDaoProvider),
    api: ref.watch(gatewaysApiServiceProvider),
  );
});

final taskCacheRepositoryProvider = Provider<TaskCacheRepository>((ref) {
  return TaskCacheRepository(
    dao: ref.watch(taskCacheDaoProvider),
    api: ref.watch(tasksApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});

final modelCacheRepositoryProvider = Provider<ModelCacheRepository>((ref) {
  return ModelCacheRepository(
    dao: ref.watch(modelCacheDaoProvider),
    api: ref.watch(modelsApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});

final skillCacheRepositoryProvider = Provider<SkillCacheRepository>((ref) {
  return SkillCacheRepository(
    dao: ref.watch(skillCacheDaoProvider),
    api: ref.watch(skillsApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});
