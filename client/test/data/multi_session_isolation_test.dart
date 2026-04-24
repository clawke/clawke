/// Multi-Session Isolation Tests
///
/// 验证 conversation_id 在 DB 层面的隔离性：
/// - 不同 conversationId 的消息不混入
/// - 同一 accountId 下多个会话互不干扰
/// - 未读计数、最后消息预览按 conversationId 独立
/// - ensureConversation 幂等性（不覆盖用户重命名）
/// - clearConversation 只删目标会话的消息
library;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/services/config_api_service.dart';

class MockWsService extends Mock implements WsService {}

class _FakeConfigApiService extends ConfigApiService {
  @override
  Future<ServerConv?> createConversation({
    String? id,
    String? name,
    String type = 'dm',
    String? accountId,
  }) async => null;
}

void main() {
  late AppDatabase db;
  late ConversationDao convDao;
  late MessageDao msgDao;
  late ConversationRepository convRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    convDao = ConversationDao(db);
    msgDao = MessageDao(db);
    convRepo = ConversationRepository(
      dao: convDao,
      api: _FakeConfigApiService(),
    );
  });

  tearDown(() => db.close());

  group('Multi-Session: Message Isolation', () {
    /// 核心测试：同一 accountId 下两个 conversationId 的消息互不可见
    test('messages with different conversationId are isolated', () async {
      // 创建两个会话（同属一个 AI 后端 "openclaw"）
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat A'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat B'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // 向 conv_a 写入 2 条消息
      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_a'),
        messageId: const Value('msg_a1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('Hello from A'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_a'),
        messageId: const Value('msg_a2'),
        accountId: const Value('openclaw'),
        senderId: const Value('agent'),
        type: const Value('text'),
        content: const Value('Reply to A'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // 向 conv_b 写入 1 条消息
      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_b'),
        messageId: const Value('msg_b1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('Hello from B'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // 验证隔离性
      final msgsA = await msgDao.watchMessages('conv_a').first;
      final msgsB = await msgDao.watchMessages('conv_b').first;

      expect(msgsA.length, 2);
      expect(msgsB.length, 1);
      expect(msgsA.every((m) => m.conversationId == 'conv_a'), isTrue);
      expect(msgsB.every((m) => m.conversationId == 'conv_b'), isTrue);
      expect(msgsA.any((m) => m.content == 'Hello from A'), isTrue);
      expect(msgsB.any((m) => m.content == 'Hello from B'), isTrue);
    });

    test('clearConversation only deletes target conversation messages', () async {
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_a'),
        messageId: const Value('msg_a1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('A message'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_b'),
        messageId: const Value('msg_b1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('B message'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // 清空 conv_a
      await msgDao.deleteByConversation('conv_a');

      final msgsA = await msgDao.watchMessages('conv_a').first;
      final msgsB = await msgDao.watchMessages('conv_b').first;

      expect(msgsA.length, 0, reason: 'conv_a should be empty after clear');
      expect(msgsB.length, 1, reason: 'conv_b should be untouched');
    });
  });

  group('Multi-Session: Unseen Count Isolation', () {
    test('unseen count increments independently per conversationId', () async {
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // conv_a 收 3 条未读
      await convDao.incrementUnseenCount('conv_a');
      await convDao.incrementUnseenCount('conv_a');
      await convDao.incrementUnseenCount('conv_a');

      // conv_b 收 1 条未读
      await convDao.incrementUnseenCount('conv_b');

      final a = await convDao.getConversation('conv_a');
      final b = await convDao.getConversation('conv_b');

      expect(a?.unseenCount, 3);
      expect(b?.unseenCount, 1);

      // 只清零 conv_a
      await convDao.resetUnseenCount('conv_a');

      final a2 = await convDao.getConversation('conv_a');
      final b2 = await convDao.getConversation('conv_b');

      expect(a2?.unseenCount, 0);
      expect(b2?.unseenCount, 1, reason: 'conv_b unseen should remain');
    });
  });

  group('Multi-Session: Last Message Isolation', () {
    test('updateLastMessage updates only target conversation', () async {
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat A'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat B'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      final now = DateTime.now().millisecondsSinceEpoch;
      await convDao.updateLastMessage(
        conversationId: 'conv_a',
        messageId: 'msg_a1',
        messageAt: now,
        preview: 'Hello from A',
      );

      final a = await convDao.getConversation('conv_a');
      final b = await convDao.getConversation('conv_b');

      expect(a?.lastMessagePreview, 'Hello from A');
      expect(a?.lastMessageId, 'msg_a1');
      expect(b?.lastMessagePreview, isNull,
          reason: 'conv_b should not be affected');
    });
  });

  group('Multi-Session: ensureConversation Idempotency', () {
    test('ensureConversation does not overwrite existing name', () async {
      // 首次创建
      await convRepo.ensureConversation(
        accountId: 'openclaw',
        type: 'ai',
        name: 'OpenClaw Agent',
      );

      // 取出自动生成的 conversationId
      final convs = await convRepo.getConversationsByAccount('openclaw');
      expect(convs, hasLength(1));
      final convId = convs.first.conversationId;

      // 用户重命名
      await convDao.updateName(convId, 'My Assistant');

      // 模拟重连：再次 ensureConversation
      await convRepo.ensureConversation(
        accountId: 'openclaw',
        type: 'ai',
        name: 'openclaw',  // 重连时用原始名
      );

      final conv = await convDao.getConversation(convId);
      expect(conv?.name, 'My Assistant',
          reason: 'ensureConversation should not overwrite user rename');
    });

    test('ensureConversation creates new conversation if not exists', () async {
      await convRepo.ensureConversation(
        accountId: 'nanobot',
        type: 'ai',
        name: 'Nanobot Agent',
      );

      final convs = await convRepo.getConversationsByAccount('nanobot');
      expect(convs, hasLength(1));
      final conv = convs.first;
      expect(conv.name, 'Nanobot Agent');
      expect(conv.accountId, 'nanobot');
      // conversationId 应为 UUID，不等于 accountId
      expect(conv.conversationId, isNot('nanobot'));
    });

    test('ensureConversation always generates UUID, never uses accountId',
        () async {
      await convRepo.ensureConversation(
        accountId: 'openclaw',
        type: 'ai',
        name: 'Agent',
      );

      // conversationId 不应等于 accountId
      final convs = await convRepo.getConversationsByAccount('openclaw');
      expect(convs, hasLength(1));
      expect(convs.first.conversationId, isNot('openclaw'));
      expect(convs.first.accountId, 'openclaw');
    });
  });

  group('Multi-Session: createConversation UUID', () {
    test('createConversation generates unique UUID per call', () async {
      final id1 = await convRepo.createConversation(
        accountId: 'openclaw',
        type: 'ai',
        name: 'Chat 1',
      );
      final id2 = await convRepo.createConversation(
        accountId: 'openclaw',
        type: 'ai',
        name: 'Chat 2',
      );

      expect(id1, isNot(equals(id2)));
      expect(id1.length, greaterThan(8)); // UUID format

      // 两个会话都存在
      final c1 = await convDao.getConversation(id1);
      final c2 = await convDao.getConversation(id2);
      expect(c1?.name, 'Chat 1');
      expect(c2?.name, 'Chat 2');
      // 同属一个 accountId
      expect(c1?.accountId, 'openclaw');
      expect(c2?.accountId, 'openclaw');
    });
  });

  group('Multi-Session: getConversationsByAccount', () {
    test('returns all conversations under the same accountId', () async {
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat A'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Chat B'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_c'),
        accountId: const Value('nanobot'),
        type: const Value('ai'),
        name: const Value('Chat C'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      final openclawConvs =
          await convDao.getConversationsByAccount('openclaw');
      final nanobotConvs =
          await convDao.getConversationsByAccount('nanobot');

      expect(openclawConvs.length, 2);
      expect(nanobotConvs.length, 1);
      expect(
        openclawConvs.every((c) => c.accountId == 'openclaw'),
        isTrue,
      );
      expect(nanobotConvs.first.name, 'Chat C');
    });
  });

  group('Multi-Session: Delete Conversation Workflow', () {
    test('clearing messages + deleting conversation leaves no orphans', () async {
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_a'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('conv_b'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_a'),
        messageId: const Value('msg_a1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('hello'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));
      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('conv_b'),
        messageId: const Value('msg_b1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('hello b'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // App workflow: clear messages → delete conversation
      await msgDao.deleteByConversation('conv_a');
      await convDao.deleteConversation('conv_a');

      // conv_a fully gone
      final convA = await convDao.getConversation('conv_a');
      expect(convA, isNull, reason: 'conv_a should be deleted');
      final msgsA = await msgDao.watchMessages('conv_a').first;
      expect(msgsA.length, 0, reason: 'conv_a messages should be gone');

      // conv_b untouched
      final convB = await convDao.getConversation('conv_b');
      expect(convB, isNotNull, reason: 'conv_b should still exist');
      final msgsB = await msgDao.watchMessages('conv_b').first;
      expect(msgsB.length, 1, reason: 'conv_b messages should remain');
    });
  });

  group('Multi-Session: Backward Compatibility', () {
    test('conversation with conversationId == accountId works (legacy mode)',
        () async {
      // 模拟旧客户端场景：conversationId 等于 accountId
      await convDao.upsertConversation(ConversationsCompanion(
        conversationId: const Value('openclaw'),
        accountId: const Value('openclaw'),
        type: const Value('ai'),
        name: const Value('Agent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      await msgDao.insertMessage(MessagesCompanion(
        conversationId: const Value('openclaw'),
        messageId: const Value('msg_1'),
        accountId: const Value('openclaw'),
        senderId: const Value('local_user'),
        type: const Value('text'),
        content: const Value('hello'),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      final msgs = await msgDao.watchMessages('openclaw').first;
      expect(msgs.length, 1);
      expect(msgs.first.conversationId, 'openclaw');
      expect(msgs.first.accountId, 'openclaw');
    });
  });
}
