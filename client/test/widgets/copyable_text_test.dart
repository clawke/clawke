import 'dart:io';

import 'package:client/widgets/copyable_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CopyableText renders content with SelectableText', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyableText('/tmp/skills/github/SKILL.md')),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data == '/tmp/skills/github/SKILL.md',
      ),
      findsOneWidget,
    );
  });

  test(
    'management detail screens route copyable content through CopyableText',
    () {
      const screenPaths = [
        'lib/screens/skills_management_screen.dart',
        'lib/screens/tasks_management_screen.dart',
        'lib/screens/skillhub_screen.dart',
      ];

      for (final path in screenPaths) {
        final source = File(path).readAsStringSync();

        expect(
          source,
          isNot(contains('SelectableText(')),
          reason:
              '$path should use CopyableText for copyable content instead of direct SelectableText.',
        );
      }
    },
  );
}
