import 'package:client/widgets/app_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showAppSnackBar limits desktop width', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSnackBar(context, '已触发任务'),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    final widget = tester.widget<SnackBar>(snackBar);
    expect(widget.behavior, SnackBarBehavior.floating);
    expect(widget.width, 480);
    expect(widget.margin, isNull);
  });

  testWidgets('showAppSnackBar keeps mobile floating margin', (tester) async {
    tester.view.physicalSize = const Size(430, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSnackBar(context, '已触发任务'),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    final widget = tester.widget<SnackBar>(snackBar);
    expect(widget.behavior, SnackBarBehavior.floating);
    expect(widget.width, isNull);
    expect(widget.margin, const EdgeInsets.fromLTRB(16, 0, 16, 16));
  });
}
