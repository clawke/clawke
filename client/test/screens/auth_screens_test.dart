import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:client/l10n/app_localizations.dart';
import 'package:client/screens/login_screen.dart';
import 'package:client/screens/forgot_password_screen.dart';

Widget _buildLocalizedApp(Widget home, {Map<String, WidgetBuilder>? routes}) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
      routes: routes ?? const <String, WidgetBuilder>{},
    ),
  );
}

void main() {
  group('LoginScreen UI', () {
    testWidgets('has tabs for login and register', (tester) async {
      await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
      await tester.pumpAndSettle();

      // Verify tabs exist
      expect(find.text('登录'), findsWidgets); // Tab label + AppBar
      expect(find.text('注册'), findsOneWidget);
    });

    testWidgets(
      'login form has email, password fields and forgot password link',
      (tester) async {
        await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
        await tester.pumpAndSettle();

        // Login tab should be active by default
        expect(find.text('邮箱地址'), findsOneWidget);
        expect(find.text('密码'), findsOneWidget);
        expect(find.text('忘记密码？'), findsOneWidget);
      },
    );

    testWidgets('register form has email, code, password fields', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
      await tester.pumpAndSettle();

      // Switch to register tab
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      expect(find.text('邮箱地址'), findsOneWidget);
      expect(find.text('验证码'), findsOneWidget);
      expect(find.text('设置密码'), findsOneWidget);
      expect(find.text('获取验证码'), findsOneWidget);
    });

    testWidgets('shows validation error if fields empty on login', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
      await tester.pumpAndSettle();

      // Tap login with empty fields
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      expect(find.text('请填写邮箱和密码'), findsOneWidget);
    });

    testWidgets('shows validation error if fields empty on register', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
      await tester.pumpAndSettle();

      // Switch to register tab
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      // Tap register with empty fields
      await tester.tap(find.widgetWithText(FilledButton, '注册'));
      await tester.pumpAndSettle();

      expect(find.text('请填写所有字段'), findsOneWidget);
    });

    testWidgets('shows validation error for send code without email', (
      tester,
    ) async {
      await tester.pumpWidget(_buildLocalizedApp(const LoginScreen()));
      await tester.pumpAndSettle();

      // Switch to register tab
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();

      // Tap "获取验证码" without email
      await tester.tap(find.text('获取验证码'));
      await tester.pumpAndSettle();

      expect(find.text('请先输入邮箱地址'), findsOneWidget);
    });

    testWidgets('forgot password link navigates to ForgotPasswordScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildLocalizedApp(
          const LoginScreen(),
          routes: {'/main': (_) => const Scaffold(body: Text('Main'))},
        ),
      );
      await tester.pumpAndSettle();

      // Tap "忘记密码？"
      await tester.tap(find.text('忘记密码？'));
      await tester.pumpAndSettle();

      // Should navigate to ForgotPasswordScreen
      expect(find.text('忘记密码'), findsOneWidget);
      expect(find.text('请输入你的注册邮箱'), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen UI', () {
    testWidgets('has step indicator and email input on Step 1', (tester) async {
      await tester.pumpWidget(_buildLocalizedApp(const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      // Step indicator
      expect(find.text('邮箱'), findsOneWidget);
      expect(find.text('验证'), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);

      // Step 1 content
      expect(find.text('请输入你的注册邮箱'), findsOneWidget);
      expect(find.text('发送验证码'), findsOneWidget);
    });

    testWidgets('shows error if email empty on Step 1', (tester) async {
      await tester.pumpWidget(_buildLocalizedApp(const ForgotPasswordScreen()));
      await tester.pumpAndSettle();

      // Tap "发送验证码" without email
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();

      expect(find.text('请先输入邮箱地址'), findsOneWidget);
    });
  });
}
