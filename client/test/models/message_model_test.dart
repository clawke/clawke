import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/message_model.dart';
import 'package:client/models/sdui_component_model.dart';

void main() {
  group('TextMessage', () {
    test('stores messageId, role, content', () {
      const msg = TextMessage(
        messageId: 'msg_1',
        role: 'agent',
        content: 'Hello',
      );
      expect(msg.messageId, 'msg_1');
      expect(msg.role, 'agent');
      expect(msg.content, 'Hello');
    });

    test('copyWith replaces content', () {
      const msg = TextMessage(
        messageId: 'msg_1',
        role: 'agent',
        content: 'Hello',
      );
      final updated = msg.copyWith(content: 'World');
      expect(updated.content, 'World');
      expect(updated.messageId, 'msg_1');
      expect(updated.role, 'agent');
    });

    test('copyWith preserves content when null', () {
      const msg = TextMessage(
        messageId: 'msg_1',
        role: 'agent',
        content: 'Hello',
      );
      final updated = msg.copyWith();
      expect(updated.content, 'Hello');
    });
  });

  group('SduiMessage', () {
    test('stores component', () {
      const component = SduiComponentModel(
        widgetName: 'MarkdownView',
        props: {'content': '# Hi'},
        actions: [],
      );
      const msg = SduiMessage(
        messageId: 'msg_2',
        role: 'agent',
        component: component,
      );
      expect(msg.component.widgetName, 'MarkdownView');
      expect(msg.component.props['content'], '# Hi');
    });
  });

  group('ErrorMessage', () {
    test('stores widgetName', () {
      const msg = ErrorMessage(
        messageId: 'msg_3',
        role: 'agent',
        widgetName: 'UnknownWidget',
      );
      expect(msg.widgetName, 'UnknownWidget');
    });
  });

  group('SystemMessage', () {
    test('stores status with optional agentName and message', () {
      const msg = SystemMessage(
        messageId: 'msg_4',
        role: 'system',
        status: 'ai_connected',
        agentName: 'coder_01',
        message: 'Ready',
      );
      expect(msg.status, 'ai_connected');
      expect(msg.agentName, 'coder_01');
      expect(msg.message, 'Ready');
    });

    test('agentName and message can be null', () {
      const msg = SystemMessage(
        messageId: 'msg_5',
        role: 'system',
        status: 'ai_disconnected',
      );
      expect(msg.agentName, isNull);
      expect(msg.message, isNull);
    });
  });
}
