import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/widgets/upgrade_prompt_widget.dart';
import '../helpers/pump_helpers.dart';

void main() {
  group('UpgradePromptWidget', () {
    testWidgets('renders warning icon', (tester) async {
      await pumpApp(
        tester,
        const UpgradePromptWidget(unknownWidgetName: 'FooWidget'),
      );
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    });

    testWidgets('displays correct fallback text', (tester) async {
      await pumpApp(
        tester,
        const UpgradePromptWidget(unknownWidgetName: 'FooWidget'),
      );
      expect(find.text('当前版本不支持组件：FooWidget，请升级客户端。'), findsOneWidget);
    });

    testWidgets('displays text for different widget name', (tester) async {
      await pumpApp(
        tester,
        const UpgradePromptWidget(unknownWidgetName: 'BarChart'),
      );
      expect(find.text('当前版本不支持组件：BarChart，请升级客户端。'), findsOneWidget);
    });

    testWidgets('long widget name does not overflow', (tester) async {
      final longName = 'A' * 200;
      await pumpApp(tester, UpgradePromptWidget(unknownWidgetName: longName));
      // No overflow error means the Expanded widget is working
      expect(find.byType(UpgradePromptWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
