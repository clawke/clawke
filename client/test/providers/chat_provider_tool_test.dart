import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/chat_provider.dart';

void main() {
  group('activeToolProvider', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeToolProvider), isNull);
    });

    test('tool_call_start sets tool name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeToolProvider.notifier).state = (
        name: 'get_weather',
        convId: 'conv_1',
      );
      expect(container.read(activeToolProvider)?.name, 'get_weather');
      expect(container.read(activeToolProvider)?.convId, 'conv_1');
    });

    test('tool_call_done clears tool name', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(activeToolProvider.notifier).state = (
        name: 'get_weather',
        convId: 'conv_1',
      );
      expect(container.read(activeToolProvider)?.name, 'get_weather');
      container.read(activeToolProvider.notifier).state = null;
      expect(container.read(activeToolProvider), isNull);
    });

    test('first text_delta clears tool name (simulated)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 模拟工具调用中
      container.read(activeToolProvider.notifier).state = (
        name: 'search_web',
        convId: 'conv_1',
      );
      expect(container.read(activeToolProvider)?.name, 'search_web');
      // 模拟首个 text_delta 到达时清除工具状态
      container.read(activeToolProvider.notifier).state = null;
      expect(container.read(activeToolProvider), isNull);
    });
  });

  group('tool_call CUP message parsing', () {
    test('tool_call_start message has expected fields', () {
      // 模拟 server 发送的 CUP 消息
      final json = {
        'payload_type': 'tool_call_start',
        'message_id': 'msg_123_tool_call',
        'tool_call_id': 'msg_123_tool',
        'tool_name': 'get_weather',
        'tool_input_summary': '',
        'account_id': 'OpenClaw',
      };
      expect(json['payload_type'], 'tool_call_start');
      expect(json['tool_name'], 'get_weather');
    });

    test('tool_call_done message has expected fields', () {
      final json = {
        'payload_type': 'tool_call_done',
        'message_id': 'msg_123_tool_done',
        'tool_call_id': 'msg_123_tool',
        'tool_name': 'get_weather',
        'status': 'completed',
        'duration_ms': 3500,
        'summary': '',
        'account_id': 'OpenClaw',
      };
      expect(json['payload_type'], 'tool_call_done');
      expect(json['tool_name'], 'get_weather');
      expect(json['status'], 'completed');
      expect(json['duration_ms'], 3500);
    });
  });
}
