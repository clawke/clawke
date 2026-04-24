import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';

import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/data/repositories/conversation_repository.dart';
import 'package:client/services/config_api_service.dart';

class MockConfigApiService extends Mock implements ConfigApiService {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ConversationDao dao;
  late MockConfigApiService mockApi;
  late ConversationRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ConversationDao(db);
    mockApi = MockConfigApiService();
    repository = ConversationRepository(dao: dao, api: mockApi);
  });

  tearDown(() async {
    await db.close();
  });

  group('Server-Authoritative Conversations Sync E2E Test', () {
    testWidgets('syncFromServer: Full sync flow (Create, Update, Delete)', (tester) async {
      // 1. Prepare Local State (One to be updated, one to be deleted)
      await dao.upsertConversation(const ConversationsCompanion(
        conversationId: Value('conv_update'),
        accountId: Value('conv_update'),
        type: Value('dm'),
        name: Value('Old Name'),
        isPinned: Value(0),
        isMuted: Value(0),
        createdAt: Value(100),
      ));

      await dao.upsertConversation(const ConversationsCompanion(
        conversationId: Value('conv_delete'),
        accountId: Value('conv_delete'),
        type: Value('dm'),
        name: Value('To Be Deleted'),
        createdAt: Value(200),
      ));

      expect((await dao.getAllConversations()).length, 2);

      // 2. Prepare Server State (One new, one to be updated, conv_delete missing)
      final serverConvs = [
        const ServerConv(
          id: 'conv_update',
          type: 'dm',
          name: 'New Name',
          isPinned: true, // changed from 0 to 1
          isMuted: true, // changed from 0 to 1
          createdAt: 100,
          updatedAt: 150,
        ),
        const ServerConv(
          id: 'conv_new',
          type: 'group',
          name: 'Newly Created',
          isPinned: false,
          isMuted: false,
          createdAt: 300,
          updatedAt: 300,
        ),
      ];

      when(() => mockApi.getConversations()).thenAnswer((_) async => serverConvs);

      // 3. Act
      await repository.syncFromServer();

      // 4. Assert
      final localList = await dao.getAllConversations();
      expect(localList.length, 2, reason: 'Should have deleted one, kept one, added one');

      final updateConv = localList.firstWhere((c) => c.conversationId == 'conv_update');
      expect(updateConv.name, 'New Name');
      expect(updateConv.isPinned, 1);
      expect(updateConv.isMuted, 1);

      final newConv = localList.firstWhere((c) => c.conversationId == 'conv_new');
      expect(newConv.name, 'Newly Created');
      expect(newConv.type, 'group');

      final deletedConv = localList.where((c) => c.conversationId == 'conv_delete').toList();
      expect(deletedConv.isEmpty, true);
    });

    testWidgets('createConversation passes client-generated UUID to server first, then local (delayed creation)', (tester) async {
      when(() => mockApi.createConversation(
        id: 'client_gen_uuid',
        name: any(named: 'name'),
        type: any(named: 'type')
      )).thenAnswer((_) async => const ServerConv(
        id: 'client_gen_uuid',
        name: 'New Chat',
        type: 'dm',
        createdAt: 0,
        updatedAt: 0,
      ));

      final createdId = await repository.createConversation(
        accountId: 'acc_1',
        type: 'dm',
        conversationId: 'client_gen_uuid',
        name: 'New Chat'
      );

      final localList = await dao.getAllConversations();
      expect(localList.length, 1);
      final localConv = localList.first;

      expect(localConv.conversationId, 'client_gen_uuid');
      expect(localConv.name, 'New Chat');
      expect(createdId, 'client_gen_uuid');

      verify(() => mockApi.createConversation(
        id: 'client_gen_uuid',
        name: 'New Chat',
        type: 'dm'
      )).called(1);
    });

    testWidgets('deleteConversation deletes on server, then local', (tester) async {
      await dao.upsertConversation(const ConversationsCompanion(
        conversationId: Value('delete_me'),
        accountId: Value('acc_1'),
        type: Value('dm'),
        createdAt: Value(100),
      ));

      when(() => mockApi.deleteConversation('delete_me')).thenAnswer((_) async => true);

      await repository.deleteConversation('delete_me');

      final localList = await dao.getAllConversations();
      expect(localList.isEmpty, true);
      verify(() => mockApi.deleteConversation('delete_me')).called(1);
    });

    testWidgets('togglePin syncs with server, then updates local', (tester) async {
      await dao.upsertConversation(const ConversationsCompanion(
        conversationId: Value('pin_me'),
        accountId: Value('acc_1'),
        type: Value('dm'),
        isPinned: Value(0),
        createdAt: Value(100),
      ));

      when(() => mockApi.updateConversation('pin_me', isPinned: true)).thenAnswer((_) async => true);

      await repository.togglePin('pin_me');

      final conv = await dao.getConversation('pin_me');
      expect(conv?.isPinned, 1);
      verify(() => mockApi.updateConversation('pin_me', isPinned: true)).called(1);
    });
  });
}
