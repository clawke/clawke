import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/sdui_component_model.dart';

void main() {
  group('ActionModel', () {
    test('fromJson parses all fields', () {
      final json = {'action_id': 'cmd_copy', 'label': '复制', 'type': 'local'};
      final action = ActionModel.fromJson(json);
      expect(action.actionId, 'cmd_copy');
      expect(action.label, '复制');
      expect(action.type, 'local');
    });

    test('toJson produces matching output', () {
      const action = ActionModel(
        actionId: 'cmd_copy',
        label: '复制',
        type: 'local',
      );
      final json = action.toJson();
      expect(json['action_id'], 'cmd_copy');
      expect(json['label'], '复制');
      expect(json['type'], 'local');
    });

    test('fromJson/toJson roundtrip is consistent', () {
      final original = {
        'action_id': 'cmd_apply',
        'label': '写入本地',
        'type': 'remote',
      };
      final action = ActionModel.fromJson(original);
      final output = action.toJson();
      expect(output, original);
    });

    test('fromJson uses defaults for missing fields', () {
      final action = ActionModel.fromJson({});
      expect(action.actionId, '');
      expect(action.label, '');
      expect(action.type, 'local');
    });
  });

  group('SduiComponentModel', () {
    test('fromJson parses all fields', () {
      final json = {
        'widget_name': 'CodeEditorView',
        'props': {'language': 'dart', 'content': 'void main() {}'},
        'actions': [
          {'action_id': 'cmd_copy', 'label': '复制', 'type': 'local'},
        ],
      };
      final model = SduiComponentModel.fromJson(json);
      expect(model.widgetName, 'CodeEditorView');
      expect(model.props['language'], 'dart');
      expect(model.actions.length, 1);
      expect(model.actions.first.actionId, 'cmd_copy');
    });

    test('toJson produces matching output', () {
      const model = SduiComponentModel(
        widgetName: 'MarkdownView',
        props: {'content': '# Hello'},
        actions: [ActionModel(actionId: 'a1', label: 'Click', type: 'local')],
      );
      final json = model.toJson();
      expect(json['widget_name'], 'MarkdownView');
      expect(json['props']['content'], '# Hello');
      expect((json['actions'] as List).length, 1);
    });

    test('fromJson/toJson roundtrip is consistent', () {
      final original = {
        'widget_name': 'MarkdownView',
        'props': {'content': 'test'},
        'actions': [
          {'action_id': 'a1', 'label': 'Go', 'type': 'remote'},
        ],
      };
      final model = SduiComponentModel.fromJson(original);
      final output = model.toJson();
      expect(output, original);
    });

    test('fromJson uses defaults for missing fields', () {
      final model = SduiComponentModel.fromJson({});
      expect(model.widgetName, 'UnknownWidget');
      expect(model.props, isEmpty);
      expect(model.actions, isEmpty);
    });

    test('fromJson parses multiple actions', () {
      final json = <String, dynamic>{
        'widget_name': 'CodeEditorView',
        'props': <String, dynamic>{},
        'actions': <Map<String, dynamic>>[
          {'action_id': 'a1', 'label': 'Copy', 'type': 'local'},
          {'action_id': 'a2', 'label': 'Apply', 'type': 'remote'},
          {'action_id': 'a3', 'label': 'Share', 'type': 'remote'},
        ],
      };
      final model = SduiComponentModel.fromJson(json);
      expect(model.actions.length, 3);
      expect(model.actions[1].actionId, 'a2');
    });

    test('fromJson handles empty map input without crash', () {
      expect(() => SduiComponentModel.fromJson({}), returnsNormally);
    });
  });
}
