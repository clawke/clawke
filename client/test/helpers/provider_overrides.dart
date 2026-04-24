import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/services/config_api_service.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/chat_provider.dart';

class MockWsService extends Mock implements WsService {}

/// 注册 mocktail 需要的 fallback values（在 setUpAll 中调用一次）
void registerTestFallbackValues() {
  registerFallbackValue(const ConversationsCompanion());
  registerFallbackValue(const MessagesCompanion());
}

class MockConversationRepository extends Mock
    implements ConversationRepository {}

class MockMessageRepository extends Mock implements MessageRepository {}

class MockConversationDao extends Mock implements ConversationDao {}

class MockMessageDao extends Mock implements MessageDao {}

class MockConfigApiService extends Mock implements ConfigApiService {}

class MockWsMessageHandler extends Mock implements WsMessageHandler {}

/// 返回 Provider overrides 和 MockWsService 实例
(List<Override>, MockWsService) wsOverrides() {
  final mock = MockWsService();

  // 默认 stub：connect 为 no-op，state 为 disconnected
  when(() => mock.connect()).thenAnswer((_) async {});
  when(() => mock.state).thenReturn(WsState.disconnected);
  when(() => mock.send(any())).thenReturn(null);
  when(() => mock.sendJson(any())).thenReturn(null);
  when(() => mock.reconnect()).thenReturn(null);
  when(() => mock.dispose()).thenReturn(null);
  when(() => mock.stateStream).thenAnswer((_) => const Stream.empty());
  when(() => mock.messageStream).thenAnswer((_) => const Stream.empty());

  final overrides = [wsServiceProvider.overrideWithValue(mock)];

  return (overrides, mock);
}

/// 创建 Conversation 测试数据
Conversation makeConversation({
  String conversationId = 'conv_1',
  String accountId = 'conv_1',
  String type = 'ai',
  String? name = 'Test Chat',
  int isPinned = 0,
  int isMuted = 0,
  int unseenCount = 0,
  int? lastMessageAt,
  String? lastMessagePreview,
}) => Conversation(
  conversationId: conversationId,
  accountId: accountId,
  type: type,
  name: name,
  isPinned: isPinned,
  isMuted: isMuted,
  unseenCount: unseenCount,
  createdAt: DateTime.now().millisecondsSinceEpoch,
  lastMessageAt: lastMessageAt,
  lastMessagePreview: lastMessagePreview,
);

/// 创建 Message 测试数据
Message makeMessage({
  String messageId = 'msg_1',
  String accountId = 'conv_1',
  String conversationId = 'conv_1',
  String senderId = 'local_user',
  String type = 'text',
  String? content = 'Hello',
  String status = 'sent',
  String? quoteId,
  int? editedAt,
}) => Message(
  messageId: messageId,
  accountId: accountId,
  conversationId: conversationId,
  senderId: senderId,
  type: type,
  content: content,
  status: status,
  quoteId: quoteId,
  editedAt: editedAt,
  createdAt: DateTime.now().millisecondsSinceEpoch,
);

/// ConversationListScreen 测试 overrides
List<Override> conversationListOverrides({
  List<Conversation>? conversations,
  String? selectedId,
}) {
  final (wsOvr, _) = wsOverrides();
  return [
    ...wsOvr,
    conversationListProvider.overrideWith(
      (ref) => Stream.value(conversations ?? []),
    ),
    if (selectedId != null)
      selectedConversationIdProvider.overrideWith((ref) => selectedId),
  ];
}

/// ChatScreen 全量 overrides
List<Override> chatScreenOverrides({
  MockWsService? mockWs,
  List<Message>? messages,
  String? selectedConvId,
  WsState wsState = WsState.disconnected,
}) {
  final ws = mockWs ?? MockWsService();

  when(() => ws.connect()).thenAnswer((_) async {});
  when(() => ws.state).thenReturn(wsState);
  when(() => ws.send(any())).thenReturn(null);
  when(() => ws.sendJson(any())).thenReturn(null);
  when(() => ws.reconnect()).thenReturn(null);
  when(() => ws.dispose()).thenReturn(null);
  when(() => ws.stateStream).thenAnswer((_) => Stream.value(wsState));
  when(
    () => ws.messageStream,
  ).thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());

  final mockConvDao = MockConversationDao();
  when(() => mockConvDao.resetUnseenCount(any())).thenAnswer((_) async {});
  when(
    () => mockConvDao.watchAll(),
  ).thenAnswer((_) => const Stream<List<Conversation>>.empty());
  when(() => mockConvDao.getConversation(any())).thenAnswer((_) async => null);
  when(() => mockConvDao.upsertConversation(any())).thenAnswer((_) async {});

  final mockMsgDao = MockMessageDao();
  when(() => mockMsgDao.getMaxSeq()).thenAnswer((_) async => 0);
  when(
    () => mockMsgDao.watchMessages(any(), limit: any(named: 'limit')),
  ).thenAnswer((_) => Stream.value(messages ?? []));

  final mockHandler = MockWsMessageHandler();
  when(() => mockHandler.trackRequest(any(), any())).thenReturn(null);
  when(() => mockHandler.dispose()).thenReturn(null);

  return [
    wsServiceProvider.overrideWithValue(ws),
    wsStateProvider.overrideWith((ref) => Stream.value(wsState)),
    selectedConversationIdProvider.overrideWith((ref) => selectedConvId),
    conversationDaoProvider.overrideWithValue(mockConvDao),
    messageDaoProvider.overrideWithValue(mockMsgDao),
    conversationRepositoryProvider.overrideWithValue(
      ConversationRepository(dao: mockConvDao, api: MockConfigApiService()),
    ),
    messageRepositoryProvider.overrideWithValue(
      MessageRepository(
        messageDao: mockMsgDao,
        conversationDao: mockConvDao,
        ws: ws,
      ),
    ),
    wsMessageHandlerProvider.overrideWithValue(mockHandler),
    chatMessagesProvider.overrideWith(
      (ref, conversationId) => Stream.value(messages ?? []),
    ),
    // 当 ws 连上时，默认也认为 AI 后端已连接
    if (wsState == WsState.connected)
      aiBackendStateProvider.overrideWith((ref) => AiBackendState.connected),
  ];
}
