import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/database_providers.dart';

/// 会话列表 — Drift .watch() 驱动
final conversationListProvider = StreamProvider<List<Conversation>>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.watchAll();
});

/// 当前选中的会话 ID
final selectedConversationIdProvider = StateProvider<String?>((ref) => null);

/// 当前选中的会话对象（从 conversationList + selectedId 派生）
final selectedConversationProvider = Provider<Conversation?>((ref) {
  final convId = ref.watch(selectedConversationIdProvider);
  if (convId == null) return null;
  final conversations = ref.watch(conversationListProvider).valueOrNull;
  return conversations?.where((c) => c.conversationId == convId).firstOrNull;
});
