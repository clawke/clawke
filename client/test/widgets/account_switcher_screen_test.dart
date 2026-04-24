import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/screens/account_switcher_screen.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/models/user_model.dart';
import 'package:client/l10n/app_localizations.dart';

void main() {
  testWidgets('AccountSwitcherScreen tap triggers provider update', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'clawke_known_accounts': jsonEncode([
        {'uid': 'user_1', 'securit': 'sec1', 'name': 'User 1'},
      ]),
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial user
    container.read(authUserProvider.notifier).state = const UserVO(
      uid: 'user_1',
      name: 'User 1',
      securit: 'sec1',
      admin: false,
      bindPhone: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AccountSwitcherScreen()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Check if the current user is User 1
    expect(find.text('User 1'), findsOneWidget);
  });
}
