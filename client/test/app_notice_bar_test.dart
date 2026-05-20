import 'package:client/widgets/app_notice_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('error notice message is selectable for copying', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppNoticeBar.error(
            message:
                'gateway_id is required when gateway native install is needed.',
            onDismiss: () {},
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data ==
                'gateway_id is required when gateway native install is needed.',
      ),
      findsOneWidget,
    );
  });
}
