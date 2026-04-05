import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/database_providers.dart';

/// 会话列表 — Drift .watch() 驱动
final conversationListProvider = StreamProvider<List<Conversation>>((ref) {
  return ref.watch(conversationRepositoryProvider).watchAll();
});

/// 当前选中的会话 ID
final selectedAccountIdProvider = StateProvider<String?>((ref) => null);
