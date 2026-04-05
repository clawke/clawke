import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/main.dart';
import 'package:client/screens/welcome_screen.dart';

void main() {
  testWidgets('ClawkeApp smoke test — no config shows WelcomeScreen', (
    WidgetTester tester,
  ) async {
    // 模拟空的 SharedPreferences（未配置状态）
    SharedPreferences.setMockInitialValues({});

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
    // 等待 FutureBuilder 完成
    await tester.pumpAndSettle();

    // 无配置时应显示 WelcomeScreen（登录/配置页）
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
