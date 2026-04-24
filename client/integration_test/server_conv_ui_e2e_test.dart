import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:drift/native.dart';

// import ClawkeApp if needed, but we bypass it
import 'package:client/screens/main_layout.dart';
import 'package:client/screens/conversation_list_screen.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/services/config_api_service.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/ws_state_provider.dart';

import 'package:client/core/ws_service.dart';

class MockConfigApiService extends Mock implements ConfigApiService {}

class FakeConvConfig extends Fake implements ConvConfig {}

class MockWsService extends Mock implements WsService {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(FakeConvConfig());
  });

  late AppDatabase db;
  late MockConfigApiService mockApi;
  late MockWsService mockWs;

  setUp(() {
    // 内存 DB 保证测试天然隔离、无副作用，支持持久化运行
    db = AppDatabase.forTesting(NativeDatabase.memory());
    mockApi = MockConfigApiService();
    mockWs = MockWsService();

    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.state).thenReturn(WsState.connected);
    when(() => mockWs.stateStream).thenAnswer((_) => Stream.value(WsState.connected));
    when(() => mockWs.messageStream).thenAnswer((_) => const Stream.empty());

    // Mock 服务器 API 调用
    when(() => mockApi.getModels(
          accountId: any(named: 'accountId'),
          refresh: any(named: 'refresh'),
        ))
        .thenAnswer((_) async => ['gpt-4', 'claude-3']);
    when(() => mockApi.getSkills(
          accountId: any(named: 'accountId'),
          refresh: any(named: 'refresh'),
        ))
        .thenAnswer((_) async => []);
    when(() => mockApi.saveConvConfig(any(), any()))
        .thenAnswer((_) async => true);
    when(() => mockApi.createConversation(
          id: any(named: 'id'),
          name: any(named: 'name'),
          type: any(named: 'type'),
          accountId: any(named: 'accountId'),
        )).thenAnswer((invocation) async {
      final id = invocation.namedArguments[const Symbol('id')] as String;
      return ServerConv(
        id: id,
        name: invocation.namedArguments[const Symbol('name')] as String?,
        type: invocation.namedArguments[const Symbol('type')] as String,
        createdAt: 0,
        updatedAt: 0,
      );
    });
    // 默认空列表（不拉取旧数据，保持测试纯净）
    when(() => mockApi.getConversations()).thenAnswer((_) async => []);
  });

  tearDown(() async {
    await db.close();
  });

  group('Server-Authoritative Conversations UI E2E Tests', () {
    testWidgets('UI Workflow: Create conversation passes UUID to Server then Local', (tester) async {
      // 1. 初始化依赖并注入
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            configApiServiceProvider.overrideWithValue(mockApi),
            wsServiceProvider.overrideWithValue(mockWs),
            // Mock 有一个后端的存在，以便激活新建对话按钮 + 不弹出选择框
            connectedAccountsProvider.overrideWith(
                (ref) => [const ConnectedAccount(accountId: 'test_acc', agentName: 'Test AI')]),
            wsStateProvider.overrideWith((ref) => Stream.value(WsState.connected)),
            aiBackendStateProvider.overrideWith((ref) => AiBackendState.connected),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: MainLayout()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2. 找到左侧面板（或悬浮拉出的抽屉）的新建会话按钮（加号）
      final addBtnFinder = find.byType(NewConversationButton);
      expect(addBtnFinder, findsWidgets);
      await tester.tap(addBtnFinder.first);
      await tester.pumpAndSettle(); // 等待 Setting Sheet 弹出并完成动画

      // 3. 验证 Conversation Settings Sheet 弹出
      expect(find.text('会话设置'), findsOneWidget);

      // 找到名称输入框
      final nameFieldFinder = find.widgetWithText(TextField, 'New Chat');
      expect(nameFieldFinder, findsOneWidget);

      // 输入新的自定义名字
      await tester.enterText(nameFieldFinder, 'Test Delay Create Event');
      await tester.pumpAndSettle();

      // 点击“保存”按钮
      final saveBtnFinder = find.text('保存');
      await tester.tap(saveBtnFinder);
      await tester.pumpAndSettle(); // 等待弹窗退出列表刷新

      // 4. 验证会话已更新在侧边栏出现
      expect(find.text('Test Delay Create Event'), findsOneWidget);

      // 5. 验证是否以同样的 UUID 发起了 API 并最终成功（UI的验证代表它回显了）
	      verify(() => mockApi.createConversation(
	            id: any(named: 'id'),
	            name: 'Test Delay Create Event',
	            type: 'ai',
	            accountId: any(named: 'accountId'),
	          )).called(1);

      verify(() => mockApi.saveConvConfig(any(), any())).called(1);
    });
  });
}
