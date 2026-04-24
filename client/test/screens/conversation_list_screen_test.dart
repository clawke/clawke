import 'package:flutter/material.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/screens/conversation_list_screen.dart';
import '../helpers/provider_overrides.dart';

void main() {
  group('ConversationListScreen', () {
    testWidgets('renders title "会话"', (tester) async {
      await _pumpScreen(tester, conversations: []);
      expect(find.text('会话'), findsOneWidget);
    });

    testWidgets('shows empty state when no conversations', (tester) async {
      await _pumpScreen(tester, conversations: []);
      expect(find.text('暂无会话'), findsOneWidget);
    });

    testWidgets('renders multiple conversations', (tester) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A'),
        makeConversation(conversationId: 'c2', accountId: 'c2', name: 'Chat B'),
        makeConversation(conversationId: 'c3', accountId: 'c3', name: 'Chat C'),
      ];
      await _pumpScreen(tester, conversations: convs);
      expect(find.text('Chat A'), findsOneWidget);
      expect(find.text('Chat B'), findsOneWidget);
      expect(find.text('Chat C'), findsOneWidget);
    });

    testWidgets('selected conversation is highlighted', (tester) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A'),
        makeConversation(conversationId: 'c2', accountId: 'c2', name: 'Chat B'),
      ];
      await _pumpScreen(tester, conversations: convs, selectedId: 'c1');

      // Find the ListTile for 'Chat A' and check it's selected
      final listTiles = tester.widgetList<ListTile>(find.byType(ListTile));
      final first = listTiles.first;
      expect(first.selected, isTrue);
    });

    testWidgets('shows unseen count badge', (tester) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A', unseenCount: 5),
      ];
      await _pumpScreen(tester, conversations: convs);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows 99+ for unseen count > 99', (tester) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A', unseenCount: 150),
      ];
      await _pumpScreen(tester, conversations: convs);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('shows pin icon for pinned conversation', (tester) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A', isPinned: 1),
      ];
      await _pumpScreen(tester, conversations: convs);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    });

    testWidgets('does not show pin icon for unpinned conversation', (
      tester,
    ) async {
      final convs = [
        makeConversation(conversationId: 'c1', accountId: 'c1', name: 'Chat A', isPinned: 0),
      ];
      await _pumpScreen(tester, conversations: convs);
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('shows loading indicator while loading', (tester) async {
      final (wsOvr, _) = wsOverrides();
      final overrides = [
        ...wsOvr,
        // Use a stream that never emits to simulate loading
        conversationListProvider.overrideWith(
          (ref) => Stream<List<Conversation>>.multi((_) {}),
        ),
      ];

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('zh'),
            home: Scaffold(body: ConversationListScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<Conversation> conversations,
  String? selectedId,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final overrides = conversationListOverrides(
    conversations: conversations,
    selectedId: selectedId,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: ConversationListScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
