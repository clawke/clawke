import 'package:flutter/material.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/models/message_model.dart';
import 'package:client/screens/chat_screen.dart';
import '../helpers/provider_overrides.dart';

void main() {
  setUpAll(() {
    registerTestFallbackValues();
  });

  group('ChatScreen', () {
    testWidgets('shows empty state when no conversation selected', (
      tester,
    ) async {
      await _pumpChatScreen(tester, selectedConvId: null);
      expect(find.text('选择一个会话'), findsOneWidget);
    });

    testWidgets('shows connected status indicator', (tester) async {
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: [],
        wsState: WsState.connected,
      );
      // Connected state shows "输入消息..." hint
      expect(find.text('输入消息...'), findsOneWidget);
    });

    testWidgets('shows disconnected status', (tester) async {
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: [],
        wsState: WsState.disconnected,
      );
      // Disconnected shows "未连接" hint
      expect(find.text('未连接'), findsOneWidget);
    });

    testWidgets('shows connecting status', (tester) async {
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: [],
        wsState: WsState.connecting,
        pumpOnly: true,
      );
      // Connecting shows "未连接" hint (not connected yet)
      expect(find.text('未连接'), findsOneWidget);
    });

    testWidgets('renders text message bubble', (tester) async {
      final messages = [
        makeMessage(
          messageId: 'msg_1',
          content: 'Hello World',
          senderId: 'agent',
          status: 'sent',
        ),
      ];
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: messages,
        wsState: WsState.connected,
      );
      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('renders deleted message placeholder', (tester) async {
      final messages = [
        makeMessage(
          messageId: 'msg_del',
          content: 'old text',
          senderId: 'local_user',
          status: 'deleted',
        ),
      ];
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: messages,
        wsState: WsState.connected,
      );
      expect(find.text('此消息已删除'), findsOneWidget);
    });

    testWidgets('shows spinner for sending status', (tester) async {
      final messages = [
        makeMessage(
          messageId: 'msg_sending',
          content: 'Sending...',
          senderId: 'local_user',
          status: 'sending',
        ),
      ];
      // Use pumpOnly: true because CircularProgressIndicator animates forever
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: messages,
        wsState: WsState.connected,
        pumpOnly: true,
      );
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows error icon for failed status', (tester) async {
      final messages = [
        makeMessage(
          messageId: 'msg_failed',
          content: 'Failed msg',
          senderId: 'local_user',
          status: 'failed',
        ),
      ];
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: messages,
        wsState: WsState.connected,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('renders streaming message', (tester) async {
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: [],
        wsState: WsState.connected,
        streamingMsg: const TextMessage(
          messageId: 'stream_1',
          role: 'agent',
          content: 'Streaming...',
        ),
      );
      expect(find.text('Streaming...'), findsOneWidget);
    });

    testWidgets('send button disabled when disconnected', (tester) async {
      await _pumpChatScreen(
        tester,
        selectedConvId: 'conv_1',
        messages: [],
        wsState: WsState.disconnected,
      );
      final sendButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.send),
      );
      expect(sendButton.onPressed, isNull);
    });
  });
}

Future<void> _pumpChatScreen(
  WidgetTester tester, {
  required String? selectedConvId,
  List<Message>? messages,
  WsState wsState = WsState.disconnected,
  TextMessage? streamingMsg,
  bool pumpOnly = false,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final overrides = [
    ...chatScreenOverrides(
      selectedConvId: selectedConvId,
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
  if (pumpOnly) {
    // Use pump() for tests with infinite animations (e.g. CircularProgressIndicator)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await tester.pumpAndSettle();
  }
}
