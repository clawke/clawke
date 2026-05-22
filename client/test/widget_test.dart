import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/main.dart';
import 'package:client/providers/server_host_provider.dart';
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
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('登录 Clawke 账号'), findsNothing);
    expect(find.text('手动配置服务器'), findsOneWidget);

    final loginCenter = tester.getCenter(find.text('登录'));
    expect((loginCenter.dx - 640).abs(), lessThan(2));
    expect(loginCenter.dy, greaterThan(360));
  });

  testWidgets(
    'WelcomeScreen scrolls on compact height without overlaying footer',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      tester.view.physicalSize = const Size(390, 520);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle();

      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ClawkeApp honors logout marker in forced direct mode', (
    WidgetTester tester,
  ) async {
    if (!shouldUseForcedServerConfig()) {
      return;
    }

    SharedPreferences.setMockInitialValues({'clawke_logged_out': true});

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  test('persisted default manual server counts as configured', () {
    expect(hasPersistedServerConfig('http://127.0.0.1:8780'), isTrue);
    expect(hasPersistedServerConfig(null), isFalse);
    expect(hasPersistedServerConfig(''), isFalse);
  });

  test('global text selection is enabled only on desktop platforms', () {
    expect(
      shouldEnableGlobalTextSelection(platform: AppPlatform.macOS),
      isTrue,
    );
    expect(
      shouldEnableGlobalTextSelection(platform: AppPlatform.windows),
      isTrue,
    );
    expect(
      shouldEnableGlobalTextSelection(platform: AppPlatform.linux),
      isTrue,
    );
    expect(shouldEnableGlobalTextSelection(platform: AppPlatform.iOS), isFalse);
    expect(
      shouldEnableGlobalTextSelection(platform: AppPlatform.android),
      isFalse,
    );
  });

  test('global text selection is disabled on web', () {
    expect(
      shouldEnableGlobalTextSelection(platform: AppPlatform.macOS, isWeb: true),
      isFalse,
    );
  });

  testWidgets('ClawkeApp wraps desktop builds in SelectionArea', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pump();

      expect(find.byType(SelectionArea), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
