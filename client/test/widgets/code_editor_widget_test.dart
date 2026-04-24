import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/widgets/code_editor_widget.dart';
import '../helpers/pump_helpers.dart';
import '../helpers/provider_overrides.dart';

void main() {
  group('CodeEditorWidget', () {
    final defaultProps = <String, dynamic>{
      'language': 'dart',
      'filename': 'main.dart',
      'content': 'void main() {}',
    };

    final defaultActions = [
      const ActionModel(actionId: 'cmd_copy', label: '复制代码', type: 'local'),
      const ActionModel(actionId: 'cmd_apply', label: '写入本地', type: 'remote'),
    ];

    testWidgets('renders filename', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: defaultActions,
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);
    });

    testWidgets('renders language label', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: defaultActions,
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('renders code content via HighlightView', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: defaultActions,
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      // HighlightView splits code into TextSpans; use textContaining
      expect(find.textContaining('main'), findsWidgets);
    });

    testWidgets('renders correct number of action buttons', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: defaultActions,
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNWidgets(2));
      expect(find.text('复制代码'), findsOneWidget);
      expect(find.text('写入本地'), findsOneWidget);
    });

    testWidgets('hides action bar when no actions', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: const [],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('copy button sets clipboard', (tester) async {
      final (overrides, _) = wsOverrides();

      // Mock clipboard platform channel
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardContent = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: const [
            ActionModel(actionId: 'cmd_copy', label: '复制代码', type: 'local'),
          ],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('复制代码'));
      await tester.pumpAndSettle();

      expect(clipboardContent, 'void main() {}');
    });

    testWidgets('remote action sends via wsService', (tester) async {
      final (overrides, mockWs) = wsOverrides();
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: defaultProps,
          actions: const [
            ActionModel(actionId: 'cmd_apply', label: '写入本地', type: 'remote'),
          ],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('写入本地'));
      await tester.pumpAndSettle();

      verify(() => mockWs.send(any())).called(1);
    });

    testWidgets('default props do not crash', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const CodeEditorWidget(
          props: {},
          actions: [],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      // defaults: filename='unknown', language='plaintext'
      expect(find.text('unknown'), findsOneWidget);
      expect(find.text('plaintext'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long code is scrollable', (tester) async {
      final (overrides, _) = wsOverrides();
      final longCode = List.generate(100, (i) => 'line $i;').join('\n');
      await pumpApp(
        tester,
        CodeEditorWidget(
          props: {
            'language': 'dart',
            'filename': 'long.dart',
            'content': longCode,
          },
          actions: const [],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      // SingleChildScrollView should be present for scrolling
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
