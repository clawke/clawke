import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';

// Re-implement the production function for testing
String deriveUidFromServer(String wsUrl) {
  final hash = sha1.convert(utf8.encode(wsUrl)).toString();
  return 's_${hash.substring(0, 6)}';
}

void main() {
  // Suppress Drift's "multiple databases" warning — we intentionally
  // create two separate in-memory DBs to test user isolation.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Per-user database isolation', () {
    late AppDatabase dbA;
    late AppDatabase dbB;
    late ConversationDao convDaoA;
    late ConversationDao convDaoB;
    late MessageDao msgDaoA;
    late MessageDao msgDaoB;

    setUp(() {
      // Simulate two different users with separate in-memory databases
      dbA = AppDatabase.forTesting(NativeDatabase.memory());
      dbB = AppDatabase.forTesting(NativeDatabase.memory());
      convDaoA = ConversationDao(dbA);
      convDaoB = ConversationDao(dbB);
      msgDaoA = MessageDao(dbA);
      msgDaoB = MessageDao(dbB);
    });

    tearDown(() async {
      await dbA.close();
      await dbB.close();
    });

    test('user A data is invisible to user B', () async {
      // User A creates a conversation
      await convDaoA.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_a1'),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          name: const Value('User A Chat'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      // User A inserts a message
      await msgDaoA.insertMessage(
        MessagesCompanion(
          conversationId: const Value('conv_a1'),
          messageId: const Value('msg_a1'),
          accountId: const Value('openclaw'),
          senderId: const Value('user_a'),
          type: const Value('text'),
          content: const Value('Hello from A'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      // Verify user A sees their data
      final listA = await convDaoA.watchAll().first;
      expect(listA.length, 1);
      expect(listA.first.name, 'User A Chat');

      final msgsA = await msgDaoA.watchMessages('conv_a1').first;
      expect(msgsA.length, 1);
      expect(msgsA.first.content, 'Hello from A');

      // Verify user B sees nothing
      final listB = await convDaoB.watchAll().first;
      expect(listB.length, 0);
    });

    test('both users can have conversations with same accountId', () async {
      // Both users connect to the same AI backend (accountId = 'openclaw')
      await convDaoA.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_a1'),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          name: const Value('A with OpenClaw'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await convDaoB.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_b1'),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          name: const Value('B with OpenClaw'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      // Each user only sees their own
      final listA = await convDaoA.watchAll().first;
      expect(listA.length, 1);
      expect(listA.first.name, 'A with OpenClaw');

      final listB = await convDaoB.watchAll().first;
      expect(listB.length, 1);
      expect(listB.first.name, 'B with OpenClaw');
    });

    test('deleting in one DB does not affect the other', () async {
      await convDaoA.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_shared'),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          name: const Value('Shared Name'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await convDaoB.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_shared'),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          name: const Value('Shared Name'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      // Delete from A
      await convDaoA.deleteConversation('conv_shared');

      // A has 0, B still has 1
      final listA = await convDaoA.watchAll().first;
      expect(listA.length, 0);

      final listB = await convDaoB.watchAll().first;
      expect(listB.length, 1);
    });

    test('message isolation across users', () async {
      // Same conversation ID in both DBs (possible when using UUID)
      final convId = 'conv_same';

      await convDaoA.upsertConversation(
        ConversationsCompanion(
          conversationId: Value(convId),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await convDaoB.upsertConversation(
        ConversationsCompanion(
          conversationId: Value(convId),
          accountId: const Value('openclaw'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDaoA.insertMessage(
        MessagesCompanion(
          conversationId: Value(convId),
          messageId: const Value('msg_a'),
          accountId: const Value('openclaw'),
          senderId: const Value('user'),
          type: const Value('text'),
          content: const Value('Message from A'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDaoB.insertMessage(
        MessagesCompanion(
          conversationId: Value(convId),
          messageId: const Value('msg_b'),
          accountId: const Value('openclaw'),
          senderId: const Value('user'),
          type: const Value('text'),
          content: const Value('Message from B'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final msgsA = await msgDaoA.watchMessages(convId).first;
      expect(msgsA.length, 1);
      expect(msgsA.first.content, 'Message from A');

      final msgsB = await msgDaoB.watchMessages(convId).first;
      expect(msgsB.length, 1);
      expect(msgsB.first.content, 'Message from B');
    });
  });

  group('deriveUidFromServer', () {
    test('same URL always returns same hash', () {
      final uid1 = deriveUidFromServer('ws://192.168.1.100:8780/ws');
      final uid2 = deriveUidFromServer('ws://192.168.1.100:8780/ws');
      expect(uid1, uid2);
    });

    test('different URLs return different hashes', () {
      final uid1 = deriveUidFromServer('ws://192.168.1.100:8780/ws');
      final uid2 = deriveUidFromServer('ws://10.0.0.5:8780/ws');
      expect(uid1, isNot(uid2));
    });

    test('localhost generates a valid uid', () {
      final uid = deriveUidFromServer('ws://127.0.0.1:8780/ws');
      expect(uid, startsWith('s_'));
      expect(uid.length, 8); // "s_" + 6 hex chars
    });

    test('uid format is s_ followed by 6 hex chars', () {
      final uid = deriveUidFromServer('wss://myserver.com/ws');
      expect(uid, matches(RegExp(r'^s_[0-9a-f]{6}$')));
    });

    test('handles empty string without error', () {
      final uid = deriveUidFromServer('');
      expect(uid, startsWith('s_'));
      expect(uid.length, 8);
    });
  });
}
