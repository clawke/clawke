import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/data/repositories/message_repository.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/ws_state_provider.dart';

import '../helpers/provider_overrides.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(registerTestFallbackValues);

  late AppDatabase db;
  late ConversationDao conversationDao;
  late MessageDao messageDao;
  late StreamController<Map<String, dynamic>> messageStreamController;
  late MockWsService mockWs;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    conversationDao = ConversationDao(db);
    messageDao = MessageDao(db);
    await db.setMetadata('last_sync_seq', '0');

    messageStreamController =
        StreamController<Map<String, dynamic>>.broadcast();
    mockWs = MockWsService();
    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.state).thenReturn(WsState.connected);
    when(() => mockWs.send(any())).thenReturn(null);
    when(() => mockWs.sendJson(any())).thenReturn(null);
    when(() => mockWs.reconnect()).thenReturn(null);
    when(() => mockWs.dispose()).thenReturn(null);
    when(() => mockWs.stateStream).thenAnswer((_) => const Stream.empty());
    when(
      () => mockWs.messageStream,
    ).thenAnswer((_) => messageStreamController.stream);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        conversationDaoProvider.overrideWithValue(conversationDao),
        messageDaoProvider.overrideWithValue(messageDao),
        wsServiceProvider.overrideWithValue(mockWs),
        conversationRepositoryProvider.overrideWithValue(
          ConversationRepository(
            dao: conversationDao,
            api: MockConfigApiService(),
          ),
        ),
        messageRepositoryProvider.overrideWithValue(
          MessageRepository(
            messageDao: messageDao,
            conversationDao: conversationDao,
            ws: mockWs,
          ),
        ),
        selectedConversationIdProvider.overrideWith((ref) => 'conv_a'),
      ],
    );
  });

  tearDown(() async {
    await messageStreamController.close();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await db.close();
  });

  test(
    'background conversation delta does not replace selected stream',
    () async {
      container.read(wsMessageHandlerProvider);

      messageStreamController.add({
        'payload_type': 'text_delta',
        'message_id': 'reply_a',
        'account_id': 'gateway',
        'conversation_id': 'conv_a',
        'content': 'A1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(container.read(streamingMessageProvider)?.content, 'A1');
      expect(
        container
            .read(streamingMessageForConversationProvider('conv_a'))
            ?.content,
        'A1',
      );
      expect(await messageDao.getMessage('reply_a'), isNull);

      messageStreamController.add({
        'payload_type': 'text_delta',
        'message_id': 'reply_b',
        'account_id': 'gateway',
        'conversation_id': 'conv_b',
        'content': 'B1',
      });
      await Future<void>.delayed(Duration.zero);

      expect(container.read(streamingMessageProvider)?.content, 'A1');
      expect(
        container
            .read(streamingMessageForConversationProvider('conv_a'))
            ?.content,
        'A1',
      );
      expect(
        container
            .read(streamingMessageForConversationProvider('conv_b'))
            ?.content,
        'B1',
      );
      expect(await messageDao.getMessage('reply_a'), isNull);
      expect(await messageDao.getMessage('reply_b'), isNull);

      messageStreamController.add({
        'payload_type': 'text_delta',
        'message_id': 'reply_a',
        'account_id': 'gateway',
        'conversation_id': 'conv_a',
        'content': 'A2',
      });
      await Future<void>.delayed(Duration.zero);

      expect(container.read(streamingMessageProvider)?.content, 'A1A2');
      expect(
        container
            .read(streamingMessageForConversationProvider('conv_a'))
            ?.content,
        'A1A2',
      );
      expect(
        container
            .read(streamingMessageForConversationProvider('conv_b'))
            ?.content,
        'B1',
      );

      messageStreamController.add({
        'payload_type': 'text_done',
        'message_id': 'reply_b_done',
        'account_id': 'gateway',
        'conversation_id': 'conv_b',
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final storedB = await messageDao.getMessage('reply_b_done');
      expect(storedB, isNotNull);
      expect(storedB!.conversationId, 'conv_b');
      expect(storedB.content, 'B1');
      expect(
        container.read(streamingMessageForConversationProvider('conv_b')),
        isNull,
      );
      expect(container.read(streamingMessageProvider)?.content, 'A1A2');
    },
  );
}
