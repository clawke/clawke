import 'package:flutter_test/flutter_test.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/widgets/widget_factory.dart';
import 'package:client/widgets/markdown_widget.dart';
import 'package:client/widgets/code_editor_widget.dart';
import 'package:client/widgets/upgrade_prompt_widget.dart';

void main() {
  group('WidgetFactory.build', () {
    test('MarkdownView returns MarkdownWidget', () {
      const component = SduiComponentModel(
        widgetName: 'MarkdownView',
        props: {'content': '# Hello'},
        actions: [],
      );
      final widget = WidgetFactory.build(component, 'msg_1');
      expect(widget, isA<MarkdownWidget>());
    });

    test('CodeEditorView returns CodeEditorWidget', () {
      const component = SduiComponentModel(
        widgetName: 'CodeEditorView',
        props: {'language': 'dart', 'content': 'void main() {}'},
        actions: [],
      );
      final widget = WidgetFactory.build(component, 'msg_2');
      expect(widget, isA<CodeEditorWidget>());
    });

    test('unknown widget name returns UpgradePromptWidget', () {
      const component = SduiComponentModel(
        widgetName: 'FutureWidget',
        props: {},
        actions: [],
      );
      final widget = WidgetFactory.build(component, 'msg_3');
      expect(widget, isA<UpgradePromptWidget>());
    });

    test('empty widget name returns UpgradePromptWidget', () {
      const component = SduiComponentModel(
        widgetName: '',
        props: {},
        actions: [],
      );
      final widget = WidgetFactory.build(component, 'msg_4');
      expect(widget, isA<UpgradePromptWidget>());
    });

    test('UnknownWidget name returns UpgradePromptWidget', () {
      const component = SduiComponentModel(
        widgetName: 'UnknownWidget',
        props: {},
        actions: [],
      );
      final widget = WidgetFactory.build(component, 'msg_5');
      expect(widget, isA<UpgradePromptWidget>());
    });
  });
}
