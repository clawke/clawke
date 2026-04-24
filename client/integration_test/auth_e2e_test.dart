import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart'; // Contains ClawkeApp

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Auth E2E Integration Tests', () {
    setUp(() async {
      // Clear shared preferences before EVERY test to ensure cold-start state
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    testWidgets('Case 1: Invalid login shows error from real backend', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final welcomeLoginButton = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      if (welcomeLoginButton.evaluate().isNotEmpty) {
        await tester.tap(welcomeLoginButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      await tester.enterText(find.widgetWithText(TextField, '邮箱地址').first, 'test_invalid@example.com');
      await tester.enterText(find.widgetWithText(TextField, '密码'), 'wrong_password');

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('Case 2: Empty registration form shows validation error', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final welcomeLoginButton = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      if (welcomeLoginButton.evaluate().isNotEmpty) {
        await tester.tap(welcomeLoginButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // Switch to Register Tab
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tap Register button without entering anything
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();

      expect(find.text('请填写所有字段'), findsOneWidget);
    });

    testWidgets('Case 3: Forgot password navigation and email validation', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final welcomeLoginButton = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      if (welcomeLoginButton.evaluate().isNotEmpty) {
        await tester.tap(welcomeLoginButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // Tap "忘记密码？"
      await tester.tap(find.text('忘记密码？'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify we are on ForgotPasswordScreen Step 1
      expect(find.text('忘记密码'), findsWidgets);
      expect(find.text('发送验证码'), findsOneWidget);

      // Try to send without email
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();

      expect(find.text('请输入邮箱地址'), findsOneWidget);
    });
  });
}
