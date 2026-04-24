import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';

void main() {
  late AppDatabase db;
  late ConversationDao convDao;
  late MessageDao msgDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    convDao = ConversationDao(db);
    msgDao = MessageDao(db);
  });

  tearDown(() => db.close());

  group('ConversationDao', () {
    test('upsert and watchAll returns conversations', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          name: const Value('Test Chat'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final list = await convDao.watchAll().first;
      expect(list.length, 1);
      expect(list.any((c) => c.name == 'Test Chat'), isTrue);
    });

    test('unseen count increments and resets', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await convDao.incrementUnseenCount('conv_1');
      await convDao.incrementUnseenCount('conv_1');

      var conv = await convDao.getConversation('conv_1');
      expect(conv?.unseenCount, 2);

      await convDao.resetUnseenCount('conv_1');
      conv = await convDao.getConversation('conv_1');
      expect(conv?.unseenCount, 0);
    });
  });

  group('MessageDao', () {
    test('insert and watch messages', () async {
      // 先创建会话
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_1'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('Hello'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final messages = await msgDao.watchMessages('conv_1').first;
      expect(messages.length, 1);
      expect(messages.first.content, 'Hello');
    });

    test('soft delete keeps message with deleted status', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_1'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('Hello'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.softDelete('msg_1');

      final messages = await msgDao.watchMessages('conv_1').first;
      expect(messages.length, 1); // 仍在列表中
      expect(messages.first.status, 'deleted'); // 但状态是 deleted，由 UI 渲染为提示
    });

    test('update status from sending to failed', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_1'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('Hello'),
          status: const Value('sending'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.updateStatus('msg_1', 'failed');

      final msg = await msgDao.getMessage('msg_1');
      expect(msg?.status, 'failed');
    });

    test('edit message updates content and editedAt', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_edit'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('original'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.updateContent('msg_edit', 'edited content');
      final msg = await msgDao.getMessage('msg_edit');
      expect(msg?.content, 'edited content');
      expect(msg?.editedAt, isNotNull);
    });

    test('getMaxSeq returns 0 when no messages with seq', () async {
      final maxSeq = await msgDao.getMaxSeq();
      expect(maxSeq, 0);
    });

    test('getMaxSeq returns highest seq', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_seq1'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('a'),
          status: const Value('sent'),
          seq: const Value(10),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_seq2'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('b'),
          status: const Value('sent'),
          seq: const Value(25),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final maxSeq = await msgDao.getMaxSeq();
      expect(maxSeq, 25);
    });

    test('updateStatus with serverId and seq', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_ack'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('hello'),
          status: const Value('sending'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.updateStatus(
        'msg_ack',
        'sent',
        serverId: 'smsg_001',
        seq: 42,
      );
      final msg = await msgDao.getMessage('msg_ack');
      expect(msg?.status, 'sent');
      expect(msg?.serverId, 'smsg_001');
      expect(msg?.seq, 42);
    });

    test('insert message with quoteId', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_original'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_1'),
          type: const Value('text'),
          content: const Value('Hello'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      await msgDao.insertMessage(
        MessagesCompanion(conversationId: const Value('conv_1'),
          messageId: const Value('msg_reply'),
          accountId: const Value('conv_1'),
          senderId: const Value('user_2'),
          type: const Value('text'),
          content: const Value('Reply'),
          quoteId: const Value('msg_original'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final msg = await msgDao.getMessage('msg_reply');
      expect(msg?.quoteId, 'msg_original');
    });
  });
}
