import 'package:client/screens/main_layout.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/nav_page_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/widgets/app_notice_bar.dart';

import '../helpers/provider_overrides.dart';

void main() {
  testWidgets('inactive indexed child is not built', (tester) async {
    var built = false;

    await tester.pumpWidget(
      buildLazyIndexedChild(
        isActive: false,
        child: Builder(
          builder: (_) {
            built = true;
            return const Text('hidden');
          },
        ),
      ),
    );

    expect(built, isFalse);
    expect(find.byType(TickerMode), findsOneWidget);
    expect(tester.widget<TickerMode>(find.byType(TickerMode)).enabled, isFalse);
    expect(find.text('hidden'), findsNothing);
  });

  testWidgets(
    'desktop chat page does not build inactive SDUI loading spinners',
    (tester) async {
      await _pumpMainLayout(tester, size: const Size(1280, 800));

      expect(
        find.byType(CircularProgressIndicator, skipOffstage: false),
        findsNothing,
      );
    },
  );

  testWidgets(
    'desktop active dashboard shows dashboard management empty state',
    (tester) async {
      await _pumpMainLayout(
        tester,
        size: const Size(1280, 800),
        activePage: NavPage.dashboard,
      );

      expect(
        find.byType(CircularProgressIndicator, skipOffstage: false),
        findsNothing,
      );
      expect(find.text('暂无已连接 Gateway'), findsOneWidget);
    },
  );

  testWidgets('desktop nav switches from dashboard back to chat page', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: _mainLayoutOverrides(activePage: NavPage.dashboard),
    );

    await _pumpMainLayoutWithContainer(
      tester,
      size: const Size(1280, 800),
      container: container,
    );

    expect(container.read(activeNavPageProvider), NavPage.dashboard);
    expect(find.text('暂无已连接 Gateway'), findsOneWidget);

    await tester.tap(find.text('会话'));
    await tester.pump();

    expect(container.read(activeNavPageProvider), NavPage.chat);
    expect(find.text('选择一个会话开始聊天'), findsOneWidget);
  });

  testWidgets('desktop chat nav item accepts clicks across the full rail row', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: _mainLayoutOverrides(activePage: NavPage.dashboard),
    );

    await _pumpMainLayoutWithContainer(
      tester,
      size: const Size(1280, 800),
      container: container,
    );

    expect(container.read(activeNavPageProvider), NavPage.dashboard);

    await tester.tapAt(const Offset(92, 82));
    await tester.pump();

    expect(container.read(activeNavPageProvider), NavPage.chat);
  });

  testWidgets('does not show global gateway disconnected alert', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final mockWs = MockWsService();
    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.state).thenReturn(WsState.connected);
    when(() => mockWs.lastError).thenReturn(null);
    when(() => mockWs.reconnect()).thenReturn(null);
    when(() => mockWs.dispose()).thenReturn(null);
    when(() => mockWs.send(any())).thenReturn(null);
    when(() => mockWs.sendJson(any())).thenReturn(null);
    when(
      () => mockWs.stateStream,
    ).thenAnswer((_) => Stream.value(WsState.connected));
    when(
      () => mockWs.messageStream,
    ).thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());

    final mockHandler = MockWsMessageHandler();
    when(() => mockHandler.dispose()).thenReturn(null);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wsServiceProvider.overrideWithValue(mockWs),
          wsStateProvider.overrideWith(
            (ref) => Stream.value(WsState.connected),
          ),
          aiBackendStateProvider.overrideWith(
            (ref) => AiBackendState.disconnected,
          ),
          wsMessageHandlerProvider.overrideWithValue(mockHandler),
          conversationListProvider.overrideWith((ref) => Stream.value([])),
          gatewayListProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MainLayout(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    expect(find.text('OpenClaw Gateway 已断开'), findsNothing);
  });

  testWidgets('uses app notice bar for server disconnected alert', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final mockWs = MockWsService();
    when(() => mockWs.connect()).thenAnswer((_) async {});
    when(() => mockWs.state).thenReturn(WsState.disconnected);
    when(() => mockWs.lastError).thenReturn('Disconnected');
    when(() => mockWs.reconnect()).thenReturn(null);
    when(() => mockWs.dispose()).thenReturn(null);
    when(() => mockWs.send(any())).thenReturn(null);
    when(() => mockWs.sendJson(any())).thenReturn(null);
    when(
      () => mockWs.stateStream,
    ).thenAnswer((_) => Stream.value(WsState.disconnected));
    when(
      () => mockWs.messageStream,
    ).thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());

    final mockHandler = MockWsMessageHandler();
    when(() => mockHandler.dispose()).thenReturn(null);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wsServiceProvider.overrideWithValue(mockWs),
          wsStateProvider.overrideWith(
            (ref) => Stream.value(WsState.disconnected),
          ),
          aiBackendStateProvider.overrideWith(
            (ref) => AiBackendState.disconnected,
          ),
          wsMessageHandlerProvider.overrideWithValue(mockHandler),
          conversationListProvider.overrideWith((ref) => Stream.value([])),
          gatewayListProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: MainLayout(),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 9));
    await tester.pump();

    final notice = tester.widget<AppNoticeBar>(find.byType(AppNoticeBar));
    expect(notice.severity, AppNoticeSeverity.error);
    expect(find.text('服务器已断开'), findsOneWidget);
    expect(find.text('请确认 Clawke Server 已启动并完成授权'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    verify(() => mockWs.reconnect()).called(1);
  });
}

Future<void> _pumpMainLayout(
  WidgetTester tester, {
  required Size size,
  NavPage? activePage,
}) async {
  SharedPreferences.setMockInitialValues({});
  await _pumpMainLayoutWithContainer(
    tester,
    size: size,
    container: ProviderContainer(
      overrides: _mainLayoutOverrides(activePage: activePage),
    ),
  );
}

Future<void> _pumpMainLayoutWithContainer(
  WidgetTester tester, {
  required Size size,
  required ProviderContainer container,
}) async {
  SharedPreferences.setMockInitialValues({});
  addTearDown(container.dispose);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: MainLayout(),
      ),
    ),
  );

  await tester.pump(const Duration(seconds: 9));
  await tester.pump();
}

List<Override> _mainLayoutOverrides({NavPage? activePage}) {
  final mockWs = MockWsService();
  when(() => mockWs.connect()).thenAnswer((_) async {});
  when(() => mockWs.state).thenReturn(WsState.connected);
  when(() => mockWs.lastError).thenReturn(null);
  when(() => mockWs.reconnect()).thenReturn(null);
  when(() => mockWs.dispose()).thenReturn(null);
  when(() => mockWs.send(any())).thenReturn(null);
  when(() => mockWs.sendJson(any())).thenReturn(null);
  when(
    () => mockWs.stateStream,
  ).thenAnswer((_) => Stream.value(WsState.connected));
  when(
    () => mockWs.messageStream,
  ).thenAnswer((_) => const Stream<Map<String, dynamic>>.empty());

  final mockHandler = MockWsMessageHandler();
  when(() => mockHandler.dispose()).thenReturn(null);

  return [
    wsServiceProvider.overrideWithValue(mockWs),
    wsStateProvider.overrideWith((ref) => Stream.value(WsState.connected)),
    aiBackendStateProvider.overrideWith((ref) => AiBackendState.connected),
    wsMessageHandlerProvider.overrideWithValue(mockHandler),
    conversationListProvider.overrideWith((ref) => Stream.value([])),
    gatewayListProvider.overrideWith((ref) => Stream.value([])),
    gatewayRepositoryProvider.overrideWithValue(_FakeGatewayRepository()),
    if (activePage != null)
      activeNavPageProvider.overrideWith((ref) => activePage),
  ];
}

class _FakeGatewayRepository implements GatewayRepository {
  @override
  Stream<List<GatewayInfo>> watchAll() => Stream.value(const []);

  @override
  Stream<List<GatewayInfo>> watchOnline() => Stream.value(const []);

  @override
  Future<List<GatewayInfo>> getOnlineGateways() async => const [];

  @override
  Future<void> syncFromServer() async {}

  @override
  Future<void> markOnline(GatewayInfo gateway) async {}

  @override
  Future<void> markOffline(String gatewayId) async {}

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {}
}
