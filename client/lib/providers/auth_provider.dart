import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/user_model.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/providers/server_host_provider.dart';

/// Auth state: logged in user or null.
final authUserProvider = StateProvider<UserVO?>((ref) => null);

/// Whether user is logged in (has persisted uid + securit).
final isLoggedInProvider = FutureProvider<bool>((ref) async {
  return AuthService.isLoggedIn();
});

/// Relay credentials (persisted).
final relayCredentialsProvider = StateProvider<RelayCredentials?>((ref) => null);

/// 当前用户的数据库隔离 ID
///
/// 优先级：
/// 1. 已登录用户 → UserVO.uid
/// 2. 手动配置（含 localhost）→ 从 wsUrl 哈希派生
final currentUserUidProvider = Provider<String>((ref) {
  // 1. 有登录用户
  final user = ref.watch(authUserProvider);
  if (user != null && user.uid.isNotEmpty) {
    debugPrint('[Auth] 🔑 currentUserUidProvider: uid=${user.uid} (from authUser: ${user.name})');
    return user.uid;
  }

  // 2. 手动配置（任何服务器地址，含 localhost）
  final config = ref.watch(serverConfigProvider);
  final derived = _deriveUidFromServer(config.wsUrl);
  debugPrint('[Auth] 🔑 currentUserUidProvider: uid=$derived (derived from ${config.wsUrl})');
  return derived;
});

/// 从服务器地址生成稳定的短 ID
/// "ws://192.168.1.100:8780/ws" → "s_a1b2c3"
String _deriveUidFromServer(String wsUrl) {
  final hash = sha1.convert(utf8.encode(wsUrl)).toString();
  return 's_${hash.substring(0, 6)}';
}
