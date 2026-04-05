import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';

/// 欢迎页语言切换集成测试。
///
/// 验证：
///   1. 欢迎页语言切换器存在
///   2. 切换到 English 后，按钮文字从中文变为英文（真实 UI 文字断言）
///   3. 切换回中文后，按钮文字恢复
///   4. 语言偏好持久化到 SharedPreferences
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Welcome Screen 语言切换 E2E', () {
    setUp(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // 清空，从欢迎页开始
    });

    testWidgets('切换语言：中文 → English，按钮文字实时更新', (tester) async {
      // 1. 启动 App，进入欢迎页
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 验证默认中文文字
      expect(find.text('登录 Clawke 账号'), findsOneWidget,
          reason: '默认语言应为中文，按钮显示"登录 Clawke 账号"');
      expect(find.text('手动配置服务器'), findsOneWidget);

      // 3. 验证语言切换器存在
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);

      // 4. 点击 English
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 5. 验证 UI 文字已真实切换为英文
      expect(find.text('Log In to Clawke'), findsOneWidget,
          reason: '切换到英文后按钮应显示 "Log In to Clawke"');
      expect(find.text('Configure Server Manually'), findsOneWidget,
          reason: '切换到英文后按钮应显示 "Configure Server Manually"');
      expect(find.text('登录 Clawke 账号'), findsNothing,
          reason: '切换到英文后中文文字应消失');

      // 6. 验证持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('clawke_locale'), equals('en'),
          reason: '切换后应持久化 en');
    });

    testWidgets('切换语言：English → 中文，按钮文字恢复', (tester) async {
      // 预先设置为英文
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('clawke_locale', 'en');

      // 1. 启动 App
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 验证英文状态
      expect(find.text('Log In to Clawke'), findsOneWidget,
          reason: '预设英文，按钮应显示英文');

      // 3. 点击切换回中文
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 4. 验证 UI 文字恢复中文
      expect(find.text('登录 Clawke 账号'), findsOneWidget,
          reason: '切回中文后应显示"登录 Clawke 账号"');
      expect(find.text('手动配置服务器'), findsOneWidget);
      expect(find.text('Log In to Clawke'), findsNothing,
          reason: '切回中文后英文文字应消失');

      // 5. 验证持久化
      expect(prefs.getString('clawke_locale'), equals('zh'));
    });
  });
}
