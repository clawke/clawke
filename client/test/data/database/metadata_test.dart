import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('Metadata (last_sync_seq storage)', () {
    test('getMetadata returns null for missing key', () async {
      final result = await db.getMetadata('nonexistent');
      expect(result, isNull);
    });

    test('setMetadata and getMetadata roundtrip', () async {
      await db.setMetadata('last_sync_seq', '42');
      final result = await db.getMetadata('last_sync_seq');
      expect(result, '42');
    });

    test('setMetadata upserts (overwrites existing)', () async {
      await db.setMetadata('last_sync_seq', '10');
      await db.setMetadata('last_sync_seq', '50');
      final result = await db.getMetadata('last_sync_seq');
      expect(result, '50');
    });

    test('multiple keys are independent', () async {
      await db.setMetadata('last_sync_seq', '100');
      await db.setMetadata('other_setting', 'hello');

      expect(await db.getMetadata('last_sync_seq'), '100');
      expect(await db.getMetadata('other_setting'), 'hello');
    });

    test('metadata is per-database (isolation)', () async {
      final dbA = AppDatabase.forTesting(NativeDatabase.memory());
      final dbB = AppDatabase.forTesting(NativeDatabase.memory());

      await dbA.setMetadata('last_sync_seq', '42');
      await dbB.setMetadata('last_sync_seq', '99');

      expect(await dbA.getMetadata('last_sync_seq'), '42');
      expect(await dbB.getMetadata('last_sync_seq'), '99');

      await dbA.close();
      await dbB.close();
    });
  });
}
