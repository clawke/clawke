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

  /// 辅助：创建会话 + 插入消息
  Future<void> seedMessage(String msgId, String content) async {
    await convDao.upsertConversation(
      ConversationsCompanion(
        conversationId: const Value('conv_1'),
        accountId: const Value('conv_1'),
        type: const Value('dm'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    await msgDao.insertMessage(
      MessagesCompanion(
        conversationId: const Value('conv_1'),
        messageId: Value(msgId),
        accountId: const Value('conv_1'),
        senderId: const Value('agent'),
        type: const Value('text'),
        content: Value(content),
        status: const Value('sent'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  group('replaceContentPattern - Approval 卡片持久化', () {
    test('精准匹配 approval 代码块并替换', () async {
      const originalContent = '好的，我来帮你删除文件。\n\n'
          '```approval\n'
          'command: rm ~/test.txt\n'
          'description: 删除测试文件\n'
          'risk: medium\n'
          '```\n\n'
          '请确认是否执行。';

      await seedMessage('msg_approval', originalContent);

      // 模拟卡片发出的 pattern（和 _respond 中的一致）
      const pattern = '```approval\n'
          'command: rm ~/test.txt\n'
          'description: 删除测试文件\n'
          'risk: medium\n'
          '```';
      const replacement = '> ✅ 已允许: rm ~/test.txt';

      await msgDao.replaceContentPattern(pattern, replacement);

      final msg = await msgDao.getMessage('msg_approval');
      expect(msg?.content, isNotNull);
      // 代码块被替换
      expect(msg!.content!.contains('```approval'), false,
          reason: 'approval 代码块应该被替换掉');
      // 替换文本存在
      expect(msg.content!.contains('✅ 已允许'), true);
      expect(msg.content!.contains('rm ~/test.txt'), true);
      // 周围文本保持不变
      expect(msg.content!.contains('好的，我来帮你删除文件'), true);
      expect(msg.content!.contains('请确认是否执行'), true);
    });

    test('pattern 不匹配时不修改消息', () async {
      const originalContent = '```approval\n'
          'command: rm ~/real.txt\n'
          'description: 真实文件\n'
          'risk: high\n'
          '```';

      await seedMessage('msg_no_match', originalContent);

      // 使用不匹配的 pattern
      const wrongPattern = '```approval\n'
          'command: rm ~/other.txt\n'
          'description: 其他文件\n'
          'risk: low\n'
          '```';

      await msgDao.replaceContentPattern(wrongPattern, '> 已允许');

      final msg = await msgDao.getMessage('msg_no_match');
      // 没有变化
      expect(msg?.content, originalContent);
    });

    test('拒绝替换', () async {
      const originalContent = '```approval\n'
          'command: rm -rf /\n'
          'description: 危险操作\n'
          'risk: high\n'
          '```';

      await seedMessage('msg_deny', originalContent);

      const pattern = '```approval\n'
          'command: rm -rf /\n'
          'description: 危险操作\n'
          'risk: high\n'
          '```';

      await msgDao.replaceContentPattern(pattern, '> 🚫 已拒绝: rm -rf /');

      final msg = await msgDao.getMessage('msg_deny');
      expect(msg!.content!.contains('🚫 已拒绝'), true);
      expect(msg.content!.contains('```approval'), false);
    });
  });

  group('replaceContentPattern - Clarify 卡片持久化', () {
    test('精准匹配 clarify 代码块并替换', () async {
      const originalContent = '```clarify\n'
          'question: 你想在哪个目录执行？\n'
          'choices:\n'
          '- /tmp\n'
          '- /home\n'
          '```';

      await seedMessage('msg_clarify', originalContent);

      const pattern = '```clarify\n'
          'question: 你想在哪个目录执行？\n'
          'choices:\n'
          '- /tmp\n'
          '- /home\n'
          '```';

      await msgDao.replaceContentPattern(pattern, '> ✅ 已选择: /tmp');

      final msg = await msgDao.getMessage('msg_clarify');
      expect(msg!.content!.contains('✅ 已选择: /tmp'), true);
      expect(msg.content!.contains('```clarify'), false);
    });
  });

  group('replaceContentPattern - 边界情况', () {
    test('空 DB 不崩溃', () async {
      // 没有任何消息
      await msgDao.replaceContentPattern('```approval\nxxx\n```', '> done');
      // 不崩溃就是通过
    });

    test('消息无 content 字段不崩溃', () async {
      await convDao.upsertConversation(
        ConversationsCompanion(
          conversationId: const Value('conv_1'),
          accountId: const Value('conv_1'),
          type: const Value('dm'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await msgDao.insertMessage(
        MessagesCompanion(
          conversationId: const Value('conv_1'),
          messageId: const Value('msg_null'),
          accountId: const Value('conv_1'),
          senderId: const Value('agent'),
          type: const Value('text'),
          status: const Value('sent'),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await msgDao.replaceContentPattern('```approval\nxxx\n```', '> done');
      // 不崩溃就是通过
    });
  });
}
