import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 响应式分页控制 — 每个会话独立 limit
final chatLimitProvider = StateProvider.family<int, String>(
  (ref, accountId) => 50,
);
