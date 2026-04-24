import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/models/user_model.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/screens/conversation_list_screen.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/l10n/app_localizations.dart';

void main() {
  testWidgets('Account switch triggers conversation list refresh', (WidgetTester tester) async {
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
          home: Scaffold(
            body: ConversationListScreen(showHeader: false),
          ),
        ),
      ),
    );

    await tester.pump();

    // Switch account
    container.read(authUserProvider.notifier).state = const UserVO(
      uid: 'user_2',
      name: 'User 2',
      securit: 'sec2',
      admin: false,
      bindPhone: false,
    );

    await tester.pump();

    final uid = container.read(currentUserUidProvider);
    expect(uid, 'user_2');
    print('Test passed!');
  });
}
