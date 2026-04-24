import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/cup_parser.dart';
import 'package:client/models/message_model.dart';
import '../helpers/cup_fixtures.dart';

void main() {
  group('CupParser.parse', () {
    test('text_delta returns TextMessage', () {
      final result = CupParser.parse(makeTextDelta());
      expect(result, isA<TextMessage>());
      final msg = result as TextMessage;
      expect(msg.messageId, 'msg_001');
      expect(msg.content, 'Hello, world!');
      expect(msg.role, 'agent');
    });

    test('text_done returns null', () {
      final result = CupParser.parse(makeTextDone());
      expect(result, isNull);
    });

    test('ui_component returns SduiMessage', () {
      final result = CupParser.parse(makeUiComponent());
      expect(result, isA<SduiMessage>());
      final msg = result as SduiMessage;
      expect(msg.messageId, 'msg_002');
      expect(msg.role, 'agent');
      expect(msg.component.widgetName, 'MarkdownView');
      expect(msg.component.props['content'], '# Hello');
      expect(msg.component.actions.length, 1);
    });

    test('ui_component with null component returns null', () {
      final json = {
        'payload_type': 'ui_component',
        'message_id': 'msg_x',
        'component': null,
      };
      final result = CupParser.parse(json);
      expect(result, isNull);
    });

    test('system_status returns SystemMessage', () {
      final result = CupParser.parse(
        makeSystemStatus(agentName: 'coder_01', message: 'Ready'),
      );
      expect(result, isA<SystemMessage>());
      final msg = result as SystemMessage;
      expect(msg.status, 'ai_connected');
      expect(msg.agentName, 'coder_01');
      expect(msg.message, 'Ready');
      expect(msg.role, 'system');
    });

    test('unknown payload_type returns null', () {
      final result = CupParser.parse({
        'payload_type': 'unknown_type',
        'message_id': 'msg_x',
      });
      expect(result, isNull);
    });

    test('missing payload_type returns null', () {
      final result = CupParser.parse({'message_id': 'msg_x'});
      expect(result, isNull);
    });

    test('malformed component triggers catch and returns null', () {
      final result = CupParser.parse(makeMalformedComponent());
      expect(result, isNull);
    });

    test('missing message_id generates unknown_ prefix fallback', () {
      final result = CupParser.parse({
        'payload_type': 'text_delta',
        'content': 'test',
      });
      expect(result, isA<TextMessage>());
      expect((result as TextMessage).messageId, startsWith('unknown_'));
    });

    test('text_delta with custom content', () {
      final result = CupParser.parse(makeTextDelta(content: '自定义内容'));
      expect((result as TextMessage).content, '自定义内容');
    });

    test('system_status with null optional fields', () {
      final result = CupParser.parse(makeSystemStatus());
      expect(result, isA<SystemMessage>());
      final msg = result as SystemMessage;
      expect(msg.agentName, isNull);
      expect(msg.message, isNull);
    });

    test('ui_component with CodeEditorView widget', () {
      final result = CupParser.parse(
        makeUiComponent(
          widgetName: 'CodeEditorView',
          props: {'language': 'dart', 'content': 'void main() {}'},
        ),
      );
      expect(result, isA<SduiMessage>());
      final msg = result as SduiMessage;
      expect(msg.component.widgetName, 'CodeEditorView');
      expect(msg.component.props['language'], 'dart');
    });
  });

  group('CupParser.isTextDone', () {
    test('returns true for text_done', () {
      expect(CupParser.isTextDone(makeTextDone()), isTrue);
    });

    test('returns false for text_delta', () {
      expect(CupParser.isTextDone(makeTextDelta()), isFalse);
    });
  });

  group('CupParser.isTextDelta', () {
    test('returns true for text_delta', () {
      expect(CupParser.isTextDelta(makeTextDelta()), isTrue);
    });

    test('returns false for text_done', () {
      expect(CupParser.isTextDelta(makeTextDone()), isFalse);
    });
  });

  group('CupParser thinking 消息', () {
    test('thinking_delta returns ThinkingMessage', () {
      final result = CupParser.parse(makeThinkingDelta());
      expect(result, isA<ThinkingMessage>());
      final msg = result as ThinkingMessage;
      expect(msg.messageId, 'msg_think_001');
      expect(msg.content, '让我分析一下...');
      expect(msg.role, 'agent');
    });

    test('thinking_done returns null', () {
      final result = CupParser.parse(makeThinkingDone());
      expect(result, isNull);
    });

    test('thinking_delta with custom content', () {
      final result = CupParser.parse(makeThinkingDelta(content: '需要考虑多个因素'));
      expect((result as ThinkingMessage).content, '需要考虑多个因素');
    });

    test('isThinkingDelta returns true for thinking_delta', () {
      expect(CupParser.isThinkingDelta(makeThinkingDelta()), isTrue);
    });

    test('isThinkingDelta returns false for text_delta', () {
      expect(CupParser.isThinkingDelta(makeTextDelta()), isFalse);
    });

    test('isThinkingDone returns true for thinking_done', () {
      expect(CupParser.isThinkingDone(makeThinkingDone()), isTrue);
    });

    test('isThinkingDone returns false for text_done', () {
      expect(CupParser.isThinkingDone(makeTextDone()), isFalse);
    });
  });

  group('ThinkingMessage.copyWith', () {
    test('更新 content', () {
      const msg = ThinkingMessage(
        messageId: 'msg_1',
        role: 'agent',
        content: '初始内容',
      );
      final updated = msg.copyWith(content: '初始内容追加内容');
      expect(updated.content, '初始内容追加内容');
      expect(updated.messageId, 'msg_1');
      expect(updated.role, 'agent');
    });

    test('不传 content 保持原值', () {
      const msg = ThinkingMessage(
        messageId: 'msg_1',
        role: 'agent',
        content: '保持不变',
      );
      final updated = msg.copyWith();
      expect(updated.content, '保持不变');
    });
  });
}
