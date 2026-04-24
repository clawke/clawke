import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';
import 'package:client/services/auth_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Happy Path E2E Tests', () {

    // 我们用一个基于时间戳的特殊邮箱，每次运行绝对不会重复
    late String uniqueEmail;
    const testPassword = 'Password123!';
    const magicCode = '111111';

    setUpAll(() {
      final now = DateTime.now().millisecondsSinceEpoch;
      uniqueEmail = 'e2e_$now@clawke.ai';
    });

    setUp(() async {
      // 保证每次从全新状态开始
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    testWidgets('Full Journey: Register -> Fetch Code -> Login Success -> Delete Account', (tester) async {
      // 1. Launch App
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 2. 欢迎页 -> 点击“登录 Clawke 账号”前往登录
      final welcomeLoginButton = find.widgetWithText(FilledButton, '登录 Clawke 账号');
      if (welcomeLoginButton.evaluate().isNotEmpty) {
        await tester.tap(welcomeLoginButton);
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      // 3. 切换到“注册” Tab
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 4. 发送验证码（虽然不用真去邮箱看，但必须让后端走一次逻辑并落表）
      await tester.enterText(find.widgetWithText(TextField, '邮箱地址').last, uniqueEmail);
      await tester.pumpAndSettle();
      await tester.tap(find.text('获取验证码'));

      // 等待请求结束（一般需要 1-2 秒），验证码按钮会倒计时
      await tester.pump(const Duration(seconds: 2));

      // 5. 填写万能验证码和新密码
      await tester.enterText(find.widgetWithText(TextField, '验证码'), magicCode);
      await tester.enterText(find.widgetWithText(TextField, '设置密码'), testPassword);
      await tester.pump(const Duration(milliseconds: 500));

      // 6. 点击注册
      final registerBtn = find.byKey(const Key('register_submit_button'));
      await tester.ensureVisible(registerBtn);
      await tester.tap(registerBtn);
      await tester.pump(const Duration(milliseconds: 500));

      // 7. 等待网络请求（注册成功会自动执行 login.json 并写入持久化，然后跳主页）
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.byIcon(Icons.settings).evaluate().isNotEmpty) {
          break; // successfully navigated
        }
      }

      // 9. UI-driven Logout Navigation Test
      await tester.tap(find.byIcon(Icons.settings).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      final textButtons = find.byType(TextButton);
      await tester.tap(textButtons.last); // Confirm logout in dialog
      await tester.pumpAndSettle(const Duration(seconds: 3)); // Wait for AuthGate rebuild

      expect(find.text('欢迎进入 Clawke'), findsWidgets, reason: 'Must successfully navigate to WelcomeScreen');

      // 10. 测试完毕，由于 E2E 在使用真实后端，我们不能留下脏数据
      // 因为前端已经顺利走完登出，我们默默用接口把账号注销删库
      final prefs = await SharedPreferences.getInstance();
      var uid = prefs.getString('clawke_auth_uid');
      expect(uid, isNull, reason: 'Logout should have cleared the token locally.');

      await AuthService.loginWithEmail(uniqueEmail, testPassword); // re-login implicitly to get cookie
      await AuthService.deleteAccount(); // nuke account
    });
  });
}
