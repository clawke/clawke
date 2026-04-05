import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';

/// 社交登录（Google / Apple）集成测试。
///
/// 由于 OAuth 需要真实用户交互（浏览器弹窗、Face ID 等），
/// 集成测试的目标是验证：
///   1. 按钮存在且可点击
///   2. 点击后不会崩溃（macOS 无 GIDClientID 曾导致 SIGABRT）
///   3. 正确显示用户友好的错误提示
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Social Login E2E - 防崩溃与错误提示验证', () {
    setUp(() async {
      // 清空状态，确保从欢迎页开始
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    testWidgets('Google 登录：点击后不崩溃，显示错误提示', (tester) async {
      // 1. 启动 App，进入欢迎页
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 点击"登录 Clawke 账号"进入登录页
      final welcomeLoginBtn = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      expect(welcomeLoginBtn, findsOneWidget, reason: '应从欢迎页开始');
      await tester.tap(welcomeLoginBtn);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 3. 验证 Google 登录按钮存在
      final googleBtn = find.text('Google 登录');
      expect(googleBtn, findsOneWidget, reason: '登录页应有 Google 登录按钮');

      // 4. 点击 Google 登录 — 不应崩溃
      await tester.tap(googleBtn);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 5. 验证显示了错误提示（macOS 上 Google 未配置 → ApiException）
      final errorIcon = find.byIcon(Icons.error_outline);
      expect(errorIcon, findsOneWidget, reason: '应显示错误提示图标');

      // 验证错误文本包含关键词
      final errorTextFinder = find.textContaining('Google');
      expect(errorTextFinder, findsWidgets, reason: '错误信息应包含 Google 关键词');
    });

    testWidgets('Apple 登录：按钮存在且点击后不崩溃', (tester) async {
      // 1. 启动 App
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 进入登录页
      final welcomeLoginBtn = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      await tester.tap(welcomeLoginBtn);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 3. 验证 Apple 登录按钮存在（macOS / iOS 平台可见）
      final appleBtn = find.text('Apple 登录');
      expect(appleBtn, findsOneWidget, reason: 'macOS/iOS 应有 Apple 登录按钮');

      // 4. 点击 Apple 登录 — 不应崩溃
      //    Apple Sign-In 会弹原生授权弹窗，在测试环境下会被取消/失败
      //    关键验证：进程不崩溃，UI 仍然响应
      await tester.tap(appleBtn);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 5. 验证 App 仍然存活（登录页仍在）
      expect(find.text('Google 登录'), findsOneWidget, reason: 'App 不应崩溃，登录页仍在');
    });
  });
}
