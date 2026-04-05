import 'package:flutter_test/flutter_test.dart';
import 'package:client/providers/upload_progress_provider.dart';

void main() {
  group('UploadProgressNotifier', () {
    late UploadProgressNotifier notifier;

    setUp(() {
      notifier = UploadProgressNotifier();
    });

    test('初始状态为空', () {
      expect(notifier.state, isEmpty);
    });

    test('update 添加进度', () {
      notifier.update('msg_1', 0.3);
      expect(notifier.state['msg_1'], 0.3);
    });

    test('update 更新进度', () {
      notifier.update('msg_1', 0.3);
      notifier.update('msg_1', 0.7);
      expect(notifier.state['msg_1'], 0.7);
    });

    test('多条消息互不干扰', () {
      notifier.update('msg_1', 0.3);
      notifier.update('msg_2', 0.8);
      expect(notifier.state['msg_1'], 0.3);
      expect(notifier.state['msg_2'], 0.8);
    });

    test('remove 删除进度', () {
      notifier.update('msg_1', 0.5);
      notifier.remove('msg_1');
      expect(notifier.state.containsKey('msg_1'), isFalse);
    });

    test('remove 不影响其他消息', () {
      notifier.update('msg_1', 0.5);
      notifier.update('msg_2', 0.8);
      notifier.remove('msg_1');
      expect(notifier.state.containsKey('msg_1'), isFalse);
      expect(notifier.state['msg_2'], 0.8);
    });

    test('完整上传流程：0% → 50% → 100% → 移除', () {
      notifier.update('msg_1', 0.0);
      expect(notifier.state['msg_1'], 0.0);

      notifier.update('msg_1', 0.5);
      expect(notifier.state['msg_1'], 0.5);

      notifier.update('msg_1', 1.0);
      expect(notifier.state['msg_1'], 1.0);

      notifier.remove('msg_1');
      expect(notifier.state, isEmpty);
    });
  });
}
