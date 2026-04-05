import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart' show GptMarkdown;
import 'package:client/widgets/markdown_widget.dart';
import '../helpers/pump_helpers.dart';
import '../helpers/provider_overrides.dart';

void main() {
  group('MarkdownWidget', () {
    testWidgets('renders props content text', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const MarkdownWidget(
          props: {'content': 'Hello Markdown'},
          actions: [],
          messageId: 'msg_1',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello Markdown'), findsOneWidget);
    });

    testWidgets('empty content does not crash', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const MarkdownWidget(props: {}, actions: [], messageId: 'msg_2'),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.byType(GptMarkdown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders bold markdown', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const MarkdownWidget(
          props: {'content': '**bold text**'},
          actions: [],
          messageId: 'msg_3',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('bold text'), findsOneWidget);
    });

    testWidgets('renders list items', (tester) async {
      final (overrides, _) = wsOverrides();
      await pumpApp(
        tester,
        const MarkdownWidget(
          props: {'content': '- item one\n- item two'},
          actions: [],
          messageId: 'msg_4',
        ),
        overrides: overrides,
      );
      await tester.pumpAndSettle();
      expect(find.text('item one'), findsOneWidget);
      expect(find.text('item two'), findsOneWidget);
    });
  });
}
