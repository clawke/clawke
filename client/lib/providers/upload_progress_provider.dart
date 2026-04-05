import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 每条消息的上传进度（0.0 ~ 1.0），按 messageId 隔离
/// 上传完成后自动移除
final uploadProgressProvider =
    StateNotifierProvider<UploadProgressNotifier, Map<String, double>>(
  (ref) => UploadProgressNotifier(),
);

class UploadProgressNotifier extends StateNotifier<Map<String, double>> {
  UploadProgressNotifier() : super({});

  void update(String messageId, double progress) {
    state = {...state, messageId: progress};
  }

  void remove(String messageId) {
    state = Map.from(state)..remove(messageId);
  }
}
