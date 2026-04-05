import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';

/// 国际化 (i18n) 全页面集成测试。
///
/// 测试策略：
///   - 已完成国际化的页面：切换语言后断言英文 UI 文字真实出现
///   - 未完成国际化的页面：用 skip: true 标记，作为待完成的 TODO 文档
///
/// ✅ WelcomeScreen      — 按钮已国际化
/// ✅ LoginScreen         — AppBar + Tab 已国际化
/// ✅ ManualConfigScreen  — AppBar + 连接按钮已国际化
/// 🚧 ForgotPasswordScreen — 待国际化（skip）
/// 🚧 已登录页面           — 需要后端 mock（skip）
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('i18n 全页面国际化验证', () {
    setUp(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    // ── WelcomeScreen ──────────────────────────────────────

    testWidgets('WelcomeScreen ✅ 默认中文', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('登录 Clawke 账号'), findsOneWidget);
      expect(find.text('手动配置服务器'), findsOneWidget);
    });

    testWidgets('WelcomeScreen ✅ 切换 English 后按钮文字更新', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Log In to Clawke'), findsOneWidget);
      expect(find.text('Configure Server Manually'), findsOneWidget);
      expect(find.text('登录 Clawke 账号'), findsNothing);
    });

    // ── LoginScreen ────────────────────────────────────────

    testWidgets('LoginScreen ✅ 默认中文：Tab 标签正确', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('登录 Clawke 账号'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('登录'), findsWidgets); // AppBar + Tab
      expect(find.text('注册'), findsOneWidget);
    });

    testWidgets('LoginScreen ✅ English 模式：Tab 标签变为英文', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.text('Log In to Clawke'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Login'), findsWidgets,
          reason: 'AppBar 和 Tab 都应显示 "Login"');
      expect(find.text('Register'), findsOneWidget,
          reason: '注册 Tab 应显示 "Register"');
      expect(find.text('注册'), findsNothing);
    });

    // TODO: 登录页内部字段（邮箱 label、密码 hint、"发送验证码"按钮等）尚未完成国际化
    // 完成后取消 skip 并添加断言
    testWidgets(
      'LoginScreen 🚧 内部字段待国际化',
      (tester) async {},
      skip: true,
    );

    // ── ManualConfigScreen ─────────────────────────────────

    testWidgets('ManualConfigScreen ✅ 默认中文：AppBar + 连接按钮', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('手动配置服务器'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('手动配置服务器'), findsWidgets); // AppBar title
      expect(find.text('连接'), findsOneWidget);
    });

    testWidgets('ManualConfigScreen ✅ English 模式：AppBar + 连接按钮变为英文',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.tap(find.text('Configure Server Manually'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Configure Server Manually'), findsWidgets,
          reason: 'AppBar 标题应为英文');
      expect(find.text('Connect'), findsOneWidget,
          reason: '连接按钮应显示 "Connect"');
      expect(find.text('连接'), findsNothing);
    });

    // TODO: ManualConfigScreen 内部字段 label（"服务器地址"、"Token（可选）"）尚未国际化
    testWidgets(
      'ManualConfigScreen 🚧 输入字段 label 待国际化',
      (tester) async {},
      skip: true,
    );

    // ── ForgotPasswordScreen ────────────────────────────────
    // TODO: 完成 ForgotPasswordScreen l10n 后验证：
    //   - AppBar title "忘记密码" → "Forgot Password"
    //   - 步骤指示器 "邮箱/验证/重置" → "Email/Verify/Reset"
    //   - 按钮 "发送验证码" → "Send Code"

    testWidgets(
      'ForgotPasswordScreen 🚧 整页待国际化',
      (tester) async {},
      skip: true,
    );

    // ── 已登录页面（需要后端 mock，暂 skip）──────────────────
    // TODO: SettingsScreen 已部分使用 AppLocalizations（t.settings / t.language 等）
    // 需要登录态，待补充 mock 后端方案后启用

    testWidgets(
      'SettingsScreen 🚧 已部分国际化，完整测试需要登录态',
      (tester) async {},
      skip: true,
    );

    testWidgets(
      'ChatScreen / MainLayout 🚧 待国际化 + 需要登录态',
      (tester) async {},
      skip: true,
    );
  });
}
