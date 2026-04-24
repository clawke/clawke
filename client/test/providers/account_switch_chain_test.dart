import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/models/user_model.dart';
import 'package:client/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Provider chain test: authUser -> currentUserUid -> database -> conversationList',
    () async {
      SharedPreferences.setMockInitialValues({});

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.watch(currentUserUidProvider);
            final db = AppDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Initial state
      final initialUid = container.read(currentUserUidProvider);

      final db1 = container.read(databaseProvider);

      // Watch conversation list to establish stream connection
      final sub = container.listen(conversationListProvider, (_, _) {});
      addTearDown(sub.close);

      // Switch account
      container.read(authUserProvider.notifier).state = const UserVO(
        uid: 'user_2',
        name: 'User 2',
        securit: 'sec2',
        admin: false,
        bindPhone: false,
      );

      // Check new state
      final newUid = container.read(currentUserUidProvider);
      expect(initialUid, isNot(newUid));
      expect(newUid, 'user_2');

      final db2 = container.read(databaseProvider);
      expect(
        db1.hashCode != db2.hashCode,
        true,
        reason: 'DB should be recreated',
      );

      // Pump event loop
      await Future.delayed(const Duration(milliseconds: 100));
    },
  );
}
