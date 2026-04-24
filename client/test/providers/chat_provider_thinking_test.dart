import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/models/message_model.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/conversation_provider.dart';
import '../helpers/provider_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUpAll(registerTestFallbackValues);

  // ── Group 1: Provider 层面 streamingThinkingProvider 状态流转 ──

  group('streamingThinkingProvider 状态流转', () {
    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('初始值为 null', () {
      expect(container.read(streamingThinkingProvider), isNull);
    });

    test('写入 ThinkingMessage 后状态非 null', () {
      container
          .read(streamingThinkingProvider.notifier)
          .state = const ThinkingMessage(
        messageId: 'think_1',
        role: 'agent',
        content: '让我想想',
      );

      final state = container.read(streamingThinkingProvider);
      expect(state, isA<ThinkingMessage>());
      expect(state!.messageId, 'think_1');
      expect(state.content, '让我想想');
    });

    test('多次追加 content 通过 copyWith 累加', () {
      const initial = ThinkingMessage(
        messageId: 'think_1',
        role: 'agent',
        content: 'A',
      );

      container.read(streamingThinkingProvider.notifier).state = initial;
      // 模拟 _appendThinkingDelta 的拼接逻辑
      final current = container.read(streamingThinkingProvider)!;
      container.read(streamingThinkingProvider.notifier).state = current
          .copyWith(content: '${current.content}B');

      final updated = container.read(streamingThinkingProvider)!;
      container.read(streamingThinkingProvider.notifier).state = updated
          .copyWith(content: '${updated.content}C');

      final result = container.read(streamingThinkingProvider)!;
      expect(result.content, 'ABC');
      expect(result.messageId, 'think_1');
    });

    test('切换 messageId 重新创建 ThinkingMessage', () {
      container
          .read(streamingThinkingProvider.notifier)
          .state = const ThinkingMessage(
        messageId: 'think_1',
        role: 'agent',
        content: '旧内容',
      );

      // 模拟不同 messageId 进来
      container
          .read(streamingThinkingProvider.notifier)
          .state = const ThinkingMessage(
        messageId: 'think_2',
        role: 'agent',
        content: '新内容',
      );

      final state = container.read(streamingThinkingProvider);
      expect(state!.messageId, 'think_2');
      expect(state.content, '新内容');
    });

    test('清除 streamingThinkingProvider 后恢复 null', () {
      container
          .read(streamingThinkingProvider.notifier)
          .state = const ThinkingMessage(
        messageId: 'think_1',
        role: 'agent',
        content: '内容',
      );

      container.read(streamingThinkingProvider.notifier).state = null;
      expect(container.read(streamingThinkingProvider), isNull);
    });
  });

  // ── Group 2: WsMessageHandler thinking 端到端流程 ──

  group('WsMessageHandler thinking 处理', () {
    late StreamController<Map<String, dynamic>> messageStreamController;
    late StreamController<List<Message>> dbMessagesController;
    late MockWsService mockWs;
    late MockMessageDao mockMsgDao;
    late MockConversationDao mockConvDao;

    setUp(() {
      messageStreamController =
          StreamController<Map<String, dynamic>>.broadcast();
      mockWs = MockWsService();
      mockMsgDao = MockMessageDao();
      mockConvDao = MockConversationDao();

      // WsService stubs
      when(() => mockWs.connect()).thenAnswer((_) async {});
      when(() => mockWs.state).thenReturn(WsState.disconnected);
      when(() => mockWs.send(any())).thenReturn(null);
      when(() => mockWs.sendJson(any())).thenReturn(null);
      when(() => mockWs.reconnect()).thenReturn(null);
      when(() => mockWs.dispose()).thenReturn(null);
      when(() => mockWs.stateStream).thenAnswer((_) => const Stream.empty());
      when(
        () => mockWs.messageStream,
      ).thenAnswer((_) => messageStreamController.stream);

      // MessageDao stubs
      dbMessagesController = StreamController<List<Message>>.broadcast();
      when(() => mockMsgDao.getMaxSeq()).thenAnswer((_) async => 0);
      when(
        () => mockMsgDao.watchMessages(any(), limit: any(named: 'limit')),
      ).thenAnswer((_) => dbMessagesController.stream);
      // 也覆盖不传 limit 的调用（_finalizeStreaming 中使用默认 limit）
      when(
        () => mockMsgDao.watchMessages(any()),
      ).thenAnswer((_) => dbMessagesController.stream);
      when(() => mockMsgDao.insertMessage(any())).thenAnswer((_) async {
        // 模拟 Drift watch 刷新：异步 emit（真实 Drift 也是 insert 后异步通知）
        Future.microtask(() => dbMessagesController.add([]));
      });
      when(
        () => mockMsgDao.updateStatus(
          any(),
          any(),
          serverId: any(named: 'serverId'),
          seq: any(named: 'seq'),
        ),
      ).thenAnswer((_) async {});

      // ConversationDao stubs
      when(() => mockConvDao.resetUnseenCount(any())).thenAnswer((_) async {});
      when(
        () => mockConvDao.watchAll(),
      ).thenAnswer((_) => const Stream<List<Conversation>>.empty());
      when(
        () => mockConvDao.getConversation(any()),
      ).thenAnswer((_) async => null);
      when(
        () => mockConvDao.upsertConversation(any()),
      ).thenAnswer((_) async {});
      when(
        () => mockConvDao.updateLastMessage(
          conversationId: any(named: 'conversationId'),
          messageId: any(named: 'messageId'),
          messageAt: any(named: 'messageAt'),
          preview: any(named: 'preview'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockConvDao.incrementUnseenCount(any()),
      ).thenAnswer((_) async {});

      // 每个测试用 setUp 创建新容器
      container = ProviderContainer(
        overrides: [
          wsServiceProvider.overrideWithValue(mockWs),
          messageDaoProvider.overrideWithValue(mockMsgDao),
          conversationDaoProvider.overrideWithValue(mockConvDao),
          conversationRepositoryProvider.overrideWithValue(
            ConversationRepository(
              dao: mockConvDao,
              api: MockConfigApiService(),
            ),
          ),
          messageRepositoryProvider.overrideWithValue(
            MessageRepository(
              messageDao: mockMsgDao,
              conversationDao: mockConvDao,
              ws: mockWs,
            ),
          ),
          selectedConversationIdProvider.overrideWith((ref) => 'conv_test'),
        ],
      );
    });

    tearDown(() async {
      // 先关闭流，确保 handler 不再收到消息
      await messageStreamController.close();
      await dbMessagesController.close();
      // 等一帧让流事件处理完
      await Future<void>.delayed(Duration.zero);
      // 然后安全 dispose 容器
      container.dispose();
    });

    test('thinking_delta 创建并拼接 streamingThinkingProvider', () async {
      // 激活 WsMessageHandler（触发 listen）
      container.read(wsMessageHandlerProvider);

      // 发送第一个 thinking_delta
      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '让我',
      });
      await Future<void>.delayed(Duration.zero);

      final state1 = container.read(streamingThinkingProvider);
      expect(state1, isNotNull);
      expect(state1!.messageId, 'think_1');
      expect(state1.content, '让我');

      // 发送第二个 thinking_delta，content 追加
      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '分析',
      });
      await Future<void>.delayed(Duration.zero);

      final state2 = container.read(streamingThinkingProvider);
      expect(state2!.content, '让我分析');
    });

    test('thinking_done 不清除 streamingThinkingProvider', () async {
      container.read(wsMessageHandlerProvider);

      // 先发 thinking_delta
      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '思考中...',
      });
      await Future<void>.delayed(Duration.zero);

      // 发 thinking_done
      messageStreamController.add({
        'payload_type': 'thinking_done',
        'message_id': 'think_1',
      });
      await Future<void>.delayed(Duration.zero);

      // thinking 内容应该保留（等 text_done 一起清除）
      final state = container.read(streamingThinkingProvider);
      expect(state, isNotNull);
      expect(state!.content, '思考中...');
    });

    test('text_done 同时清除 streaming 和 thinking 状态', () async {
      container.read(wsMessageHandlerProvider);

      // 1. thinking 阶段
      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '思考...',
      });
      await Future<void>.delayed(Duration.zero);

      messageStreamController.add({
        'payload_type': 'thinking_done',
        'message_id': 'think_1',
      });
      await Future<void>.delayed(Duration.zero);

      // 2. text 阶段
      messageStreamController.add({
        'payload_type': 'text_delta',
        'message_id': 'msg_1',
        'account_id': 'conv_test',
        'content': '回答',
      });
      await Future<void>.delayed(Duration.zero);

      expect(container.read(streamingMessageProvider), isNotNull);
      expect(container.read(streamingThinkingProvider), isNotNull);

      // 3. text_done — 清除全部流式状态
      messageStreamController.add({
        'payload_type': 'text_done',
        'message_id': 'msg_1',
        'account_id': 'conv_test',
      });
      // 等持久化异步完成 + DB watch 触发 thinking 清除
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(streamingMessageProvider), isNull);
      expect(container.read(streamingThinkingProvider), isNull);
    });

    test('thinking_delta 不影响 streamingMessageProvider', () async {
      container.read(wsMessageHandlerProvider);

      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '分析问题',
      });
      await Future<void>.delayed(Duration.zero);

      // thinking 不应写入 streamingMessageProvider
      expect(container.read(streamingMessageProvider), isNull);
      expect(container.read(streamingThinkingProvider), isNotNull);
    });

    test('不同 messageId 的 thinking_delta 替换旧内容', () async {
      container.read(wsMessageHandlerProvider);

      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_1',
        'content': '旧思考',
      });
      await Future<void>.delayed(Duration.zero);

      messageStreamController.add({
        'payload_type': 'thinking_delta',
        'message_id': 'think_2',
        'content': '新思考',
      });
      await Future<void>.delayed(Duration.zero);

      final state = container.read(streamingThinkingProvider);
      expect(state!.messageId, 'think_2');
      expect(state.content, '新思考');
    });
  });
}
