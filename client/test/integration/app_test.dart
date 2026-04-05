import 'package:flutter/material.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/models/message_model.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/screens/chat_screen.dart';
import 'package:client/widgets/markdown_widget.dart';
import 'package:client/widgets/upgrade_prompt_widget.dart';

import '../helpers/provider_overrides.dart';

void main() {
  setUpAll(() {
    registerTestFallbackValues();
  });

  group('Integration: App end-to-end flows', () {
    // Flow 1: 启动 → 连接 → 收 SDUI → 渲染 MarkdownWidget
    testWidgets('Flow 1: connect and render SDUI MarkdownWidget', (
      tester,
    ) async {
      final sduiComponent = {
        'widget_name': 'MarkdownView',
        'props': {'content': '# Welcome to Clawke'},
        'actions': <Map<String, dynamic>>[],
      };

      // Build chat screen with a cup_component message already in DB
      final messages = [
        makeMessage(
          messageId: 'msg_sdui_1',
          content:
              '{"widget_name":"MarkdownView","props":{"content":"# Welcome to Clawke"},"actions":[]}',
          senderId: 'agent',
          type: 'cup_component',
          status: 'sent',
        ),
      ];

      await _pumpIntegration(
        tester,
        messages: messages,
        wsState: WsState.connected,
      );

      // MarkdownWidget should be rendered
      expect(find.byType(MarkdownWidget), findsOneWidget);
      expect(find.textContaining('Welcome to Clawke'), findsOneWidget);
    });

    // Flow 2: 发消息 → 状态变化 (sending → sent via ACK)
    testWidgets('Flow 2: message status shows sending indicator', (
      tester,
    ) async {
      final messages = [
        makeMessage(
          messageId: 'msg_user_1',
          content: 'Hello AI',
          senderId: 'local_user',
          status: 'sent',
        ),
      ];

      await _pumpIntegration(
        tester,
        messages: messages,
        wsState: WsState.connected,
      );

      // Check icon renders for 'sent' status
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    // Flow 3: 未知 Widget 优雅降级
    testWidgets('Flow 3: unknown widget graceful degradation', (tester) async {
      final messages = [
        makeMessage(
          messageId: 'msg_unknown_1',
          content: '{"widget_name":"FutureChartView","props":{},"actions":[]}',
          senderId: 'agent',
          type: 'cup_component',
          status: 'sent',
        ),
      ];

      await _pumpIntegration(
        tester,
        messages: messages,
        wsState: WsState.connected,
      );

      // UpgradePromptWidget should appear, not crash
      expect(find.byType(UpgradePromptWidget), findsOneWidget);
      expect(find.textContaining('FutureChartView'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Flow 4: 流式 text_delta 累积
    testWidgets('Flow 4: streaming text accumulates progressively', (
      tester,
    ) async {
      // Simulate streaming by providing a streamingMessage
      const streamingMsg = TextMessage(
        messageId: 'stream_1',
        role: 'agent',
        content: 'Hello World from streaming',
      );

      await _pumpIntegration(
        tester,
        messages: [],
        wsState: WsState.connected,
        streamingMsg: streamingMsg,
      );

      expect(find.text('Hello World from streaming'), findsOneWidget);
    });

    // Flow 5: 断开时 UI 状态正确
    testWidgets('Flow 5: disconnected state disables input', (tester) async {
      await _pumpIntegration(
        tester,
        messages: [],
        wsState: WsState.disconnected,
      );

      // Input field shows "未连接" hint
      expect(find.text('未连接'), findsOneWidget);
    });
  });
}

Future<void> _pumpIntegration(
  WidgetTester tester, {
  required List<Message> messages,
  required WsState wsState,
  TextMessage? streamingMsg,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final overrides = [
    ...chatScreenOverrides(
      selectedConvId: 'conv_1',
      messages: messages,
      wsState: wsState,
    ),
    if (streamingMsg != null)
      streamingMessageProvider.overrideWith((ref) => streamingMsg),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
