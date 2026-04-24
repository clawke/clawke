import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';
import 'package:client/services/auth_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Modify Password E2E', () {
    const oldPassword = 'Password123!';
    const newPassword = 'Password999!';
    const magicCode = '111111';

    setUp(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    });

    testWidgets('Change password flow: register via API -> use UI to change -> test new login -> delete', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final uniqueEmail = 'e2emod_$now@clawke.ai';

      // 1. Programmatically register and login
      await AuthService.sendVerificationCode(uniqueEmail);
      await Future.delayed(const Duration(milliseconds: 500));
      await AuthService.registerWithEmail(uniqueEmail, magicCode, oldPassword);

      // 2. Launch App (AuthGate should land on MainLayout because we injected the user)
      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // 3. Find Settings icon and go to Settings
      final settingsIcon = find.byIcon(Icons.settings);
      expect(settingsIcon, findsWidgets, reason: 'Should land on MainLayout after programmatic login');
      await tester.tap(settingsIcon.first);
      await tester.pumpAndSettle();

      // 4. Tap '修改密码' list tile
      final modPwdRow = find.text('修改密码');
      await tester.ensureVisible(modPwdRow);
      await tester.tap(modPwdRow);
      await tester.pumpAndSettle();

      // 5. Fill out the password change form
      await tester.enterText(find.widgetWithText(TextFormField, '当前密码'), oldPassword);
      await tester.enterText(find.widgetWithText(TextFormField, '新密码'), newPassword);
      await tester.enterText(find.widgetWithText(TextFormField, '确认新密码'), newPassword);
      await tester.pump(const Duration(milliseconds: 500));

      // 6. Submit
      final submitBtn = find.byKey(const Key('modify_pwd_submit_btn'));
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);

      // Wait for network request and navigation back out of the app to WelcomeScreen
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('登录 Clawke 账号').evaluate().isNotEmpty) {
          break; // successfully navigated to WelcomeScreen after logout
        }
      }

      // 7. Verify we are logged out in UI
      expect(find.text('登录 Clawke 账号'), findsWidgets, reason: 'Should redirect to WelcomeScreen after password change');

      // 8. Programmatically verify old password fails
      bool oldPwdFailed = false;
      try {
        await AuthService.loginWithEmail(uniqueEmail, oldPassword);
      } catch (e) {
        oldPwdFailed = true;
      }
      expect(oldPwdFailed, isTrue, reason: 'Old password must fail now');

      // 9. Programmatically verify new password works
      final user = await AuthService.loginWithEmail(uniqueEmail, newPassword);
      expect(user.uid, isNotEmpty, reason: 'New password must allow login');

      // 10. Cleanup
      await AuthService.deleteAccount();
    });
  });
}
