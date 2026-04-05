import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/ws_service.dart';

// WsService 单例 Provider
final wsServiceProvider = Provider<WsService>((ref) {
  final service = WsService();
  ref.onDispose(service.dispose);
  return service;
});

// 连接状态 Provider
final wsStateProvider = StreamProvider<WsState>((ref) {
  final service = ref.watch(wsServiceProvider);
  return service.stateStream;
});

// 流式消息流 Provider
final wsMessageStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final service = ref.watch(wsServiceProvider);
  return service.messageStream;
});

// AI 后端（OpenClaw）连接状态
enum AiBackendState { unknown, connected, disconnected }

final aiBackendStateProvider = StateProvider<AiBackendState>(
  (ref) => AiBackendState.unknown,
);
