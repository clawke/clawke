import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/user_model.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/screens/main_layout.dart';
import 'package:client/services/auth_service.dart';

const _mockControlUrl = String.fromEnvironment('CLAWKE_E2E_MOCK_CONTROL_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final appBoundaryKey = GlobalKey();

  const caseFile = String.fromEnvironment('CLAWKE_E2E_CASE_FILE');
  const caseJsonBase64 = String.fromEnvironment('CLAWKE_E2E_CASE_JSON_BASE64');
  const httpUrl = String.fromEnvironment('CLAWKE_E2E_HTTP_URL');
  const wsUrl = String.fromEnvironment('CLAWKE_E2E_WS_URL');
  const runDir = String.fromEnvironment('CLAWKE_E2E_RUN_DIR');

  group('UI E2E', () {
    testWidgets(
      'runs case manifest from real Clawke UI',
      (tester) async {
        final testCase = _loadCase(
          caseFile: caseFile,
          caseJsonBase64: caseJsonBase64,
        );
        final serverConfig = _loadServerConfig(
          httpUrl: httpUrl,
          wsUrl: wsUrl,
          testCase: testCase,
        );
        _configureMockAuth(testCase);
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          RepaintBoundary(
            key: appBoundaryKey,
            child: ProviderScope(
              overrides: [
                serverConfigProvider.overrideWith(
                  (ref) => ServerConfigNotifier(
                    initialConfig: serverConfig,
                    loadFromPrefs: false,
                  ),
                ),
                localeProvider.overrideWith(
                  (ref) => LocaleNotifier(
                    initialLocale: const Locale('zh'),
                    loadFromPrefs: false,
                  ),
                ),
              ],
              child: const MaterialApp(
                debugShowCheckedModeBanner: false,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MainLayout(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));

        try {
          for (final step in (testCase['steps'] as List)) {
            final normalizedStep = Map<String, dynamic>.from(step as Map);
            debugPrint('[UI E2E] step start: ${jsonEncode(normalizedStep)}');
            await _runStep(tester, normalizedStep);
            debugPrint('[UI E2E] step done: ${jsonEncode(normalizedStep)}');
          }
          for (final assertion in (testCase['assert'] as List)) {
            final normalizedAssert = Map<String, dynamic>.from(
              assertion as Map,
            );
            debugPrint(
              '[UI E2E] assert start: ${jsonEncode(normalizedAssert)}',
            );
            await _runAssert(tester, normalizedAssert);
            debugPrint('[UI E2E] assert done: ${jsonEncode(normalizedAssert)}');
          }
          await _captureScreenshot(tester, appBoundaryKey, runDir, 'final');
        } catch (_) {
          await _captureScreenshot(tester, appBoundaryKey, runDir, 'failure');
          rethrow;
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Map<String, dynamic> _loadCase({
  required String caseFile,
  required String caseJsonBase64,
}) {
  if (caseJsonBase64.isNotEmpty) {
    final raw = utf8.decode(base64Decode(caseJsonBase64));
    return jsonDecode(raw) as Map<String, dynamic>;
  }
  if (caseFile.isEmpty) {
    throw StateError(
      'CLAWKE_E2E_CASE_JSON_BASE64 or CLAWKE_E2E_CASE_FILE is required',
    );
  }
  return jsonDecode(File(caseFile).readAsStringSync()) as Map<String, dynamic>;
}

ServerConfig _loadServerConfig({
  required String httpUrl,
  required String wsUrl,
  required Map<String, dynamic> testCase,
}) {
  if (httpUrl.isEmpty || wsUrl.isEmpty) {
    throw StateError('CLAWKE_E2E_HTTP_URL and CLAWKE_E2E_WS_URL are required');
  }
  final setup = (testCase['setup'] as Map?)?.cast<String, dynamic>() ?? {};
  return ServerConfig(
    httpUrl: httpUrl,
    wsUrl: wsUrl,
    token: (setup['clientToken'] as String?) ?? '',
  );
}

void _configureMockAuth(Map<String, dynamic> testCase) {
  final mockAuth = (testCase['mockAuth'] as Map?)?.cast<String, dynamic>();
  final rawRelay = (mockAuth?['relayCredentials'] as Map?)
      ?.cast<String, dynamic>();
  if (rawRelay == null) {
    AuthService.setRelayCredentialsFetcherForTesting(null);
    return;
  }

  AuthService.setRelayCredentialsFetcherForTesting(() async {
    return RelayCredentials.fromJson(rawRelay);
  });
}

Future<void> _runStep(WidgetTester tester, Map<String, dynamic> step) async {
  switch (step['action'] as String) {
    case 'launch_app':
      await tester.pump(const Duration(seconds: 2));
      return;
    case 'wait_for_text':
      await _waitForText(
        tester,
        step['text'] as String,
        timeout: _stepTimeout(step),
      );
      return;
    case 'wait_for_absent_text':
      await _waitForAbsentText(
        tester,
        step['text'] as String,
        duration: _stepDuration(step),
      );
      return;
    case 'wait_for_key':
      await _waitForKey(
        tester,
        step['key'] as String,
        timeout: _stepTimeout(step),
      );
      return;
    case 'tap_key':
      await _tapKey(tester, step['key'] as String);
      return;
    case 'tap_text':
      await _tapText(
        tester,
        step['text'] as String,
        exact: step['exact'] == true,
        preferLast: step['preferLast'] == true,
      );
      return;
    case 'tap_filter_chip':
      await _tapFilterChip(tester, step['text'] as String);
      return;
    case 'tap_dialog_button':
      await _tapButtonText(tester, step['text'] as String, preferLast: true);
      return;
    case 'enter_text_field':
      await _enterTextField(
        tester,
        key: step['key'] as String?,
        index: step['index'] as int?,
        text: step['text'] as String,
        formField: step['formField'] != false,
      );
      return;
    case 'tap_card_button':
      await _tapCardButton(
        tester,
        cardText: step['cardText'] as String,
        buttonText: step['buttonText'] as String,
      );
      return;
    case 'tap_card_tooltip':
      await _tapCardTooltip(
        tester,
        cardText: step['cardText'] as String,
        tooltip: step['tooltip'] as String,
      );
      return;
    case 'tap_card_switch':
      await _tapCardSwitch(tester, step['cardText'] as String);
      return;
    case 'pump':
      await tester.pump(Duration(milliseconds: step['durationMs'] as int));
      return;
    case 'wait_for_absent_key':
      await _waitForAbsentKey(
        tester,
        step['key'] as String,
        duration: _stepDuration(step),
      );
      return;
    case 'wait_for_icon':
      await _waitForIcon(
        tester,
        step['icon'] as String,
        timeout: _stepTimeout(step),
      );
      return;
    case 'wait_for_absent_icon':
      await _waitForAbsentIcon(
        tester,
        step['icon'] as String,
        duration: _stepDuration(step),
      );
      return;
    case 'wait_for_conversation_unread':
      await _waitForConversationUnread(
        tester,
        name: step['name'] as String,
        count: step['count'] as int,
        timeout: _stepTimeout(step),
      );
      return;
    case 'wait_for_conversation_unread_absent':
      await _waitForConversationUnreadAbsent(
        tester,
        name: step['name'] as String,
        count: step['count'] as int,
        duration: _stepDuration(step),
      );
      return;
    case 'wait_for_nav_unread':
      await _waitForNavUnread(
        tester,
        label: step['label'] as String,
        count: step['count'] as int,
        timeout: _stepTimeout(step),
      );
      return;
    case 'wait_for_nav_unread_absent':
      await _waitForNavUnreadAbsent(
        tester,
        label: step['label'] as String,
        count: step['count'] as int,
        duration: _stepDuration(step),
      );
      return;
    case 'tap_icon':
      await _tapIcon(tester, step['icon'] as String);
      return;
    case 'create_conversation':
      await _createConversation(tester, step);
      return;
    case 'send_message':
      await _sendMessage(tester, step['text'] as String);
      return;
    case 'mock_gateway_push':
      await _mockGatewayPush(step);
      await tester.pump(const Duration(milliseconds: 300));
      return;
    case 'simulate_remote_push':
      await _simulateRemotePush(tester, step);
      return;
    case 'delete_conversation':
      await _deleteConversation(tester, step['name'] as String);
      return;
    default:
      throw UnsupportedError('Unknown UI E2E action: ${step['action']}');
  }
}

Future<void> _runAssert(
  WidgetTester tester,
  Map<String, dynamic> assertion,
) async {
  final text = assertion['uiTextVisible'] as String?;
  if (text != null) {
    await _waitForText(tester, text);
    expect(find.textContaining(text), findsWidgets);
    return;
  }
  final absentText = assertion['uiTextAbsent'] as String?;
  if (absentText != null) {
    await _waitForAbsentText(tester, absentText);
    expect(find.textContaining(absentText), findsNothing);
    return;
  }
  throw UnsupportedError('Unknown UI E2E assertion: $assertion');
}

Future<void> _simulateRemotePush(
  WidgetTester tester,
  Map<String, dynamic> step,
) async {
  final conversationId = _resolveNotificationConversationId(tester, step);
  final payload = {
    'conversation_id': conversationId,
    'message_id': step['message_id'] as String,
    'gateway_id': step['gateway_id'] as String,
    'seq': step['seq'] as int? ?? 0,
    'event_type': step['event_type'] as String? ?? 'notification_tap',
  };
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall('remotePushReceived', payload),
  );
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage('clawke/push', message, (_) {});
  await tester.pump(const Duration(seconds: 2));
}

String _resolveNotificationConversationId(
  WidgetTester tester,
  Map<String, dynamic> step,
) {
  final explicitId = step['conversation_id'] as String?;
  if (explicitId != null && explicitId.trim().isNotEmpty) {
    return explicitId;
  }

  final name = step['conversation_name'] as String?;
  if (name == null || name.trim().isEmpty) {
    throw TestFailure(
      'simulate_remote_push requires conversation_id or conversation_name',
    );
  }

  final context = tester.element(find.byType(MainLayout));
  final container = ProviderScope.containerOf(context);
  final conversations =
      container.read(conversationListProvider).valueOrNull ?? const [];
  for (final conversation in conversations) {
    final displayName = conversation.name ?? conversation.accountId;
    if (displayName == name || conversation.conversationId == name) {
      return conversation.conversationId;
    }
  }

  throw TestFailure('Conversation not found for notification payload: $name');
}

Future<void> _createConversation(
  WidgetTester tester,
  Map<String, dynamic> step,
) async {
  final name = step['name'] as String;
  await _tapFinder(tester, find.byTooltip('新建会话'));
  await _waitForText(tester, '新建会话');

  final nameField = find.byType(TextField);
  await _waitForFinder(tester, nameField);
  await tester.ensureVisible(nameField.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(nameField.first, name);
  await tester.pump(const Duration(milliseconds: 300));

  final model = step['model'] as String?;
  if (model != null && model.isNotEmpty) {
    await _selectConversationModel(tester, model);
  }

  final skills = _stringList(step['skills']);
  if (skills.isNotEmpty) {
    await _selectConversationSkills(
      tester,
      skills,
      searchQuery: step['skillSearchQuery'] as String?,
      absentAfterSearch: _stringList(step['skillSearchAbsent']),
    );
  }

  await _tapButtonText(tester, '创建');
  await tester.pump(const Duration(seconds: 2));
  await _waitForText(tester, name);
}

Future<void> _selectConversationModel(WidgetTester tester, String model) async {
  await _tapFirstAvailable(tester, [
    find.byIcon(Icons.layers_rounded),
    find.textContaining('默认模型'),
  ]);
  await _waitForText(tester, '选择模型');
  await _waitForText(tester, model, timeout: const Duration(seconds: 30));
  await _tapFinder(tester, find.text(model));
  await _waitForText(tester, '新建会话');
  await _waitForText(tester, model);
}

Future<void> _selectConversationSkills(
  WidgetTester tester,
  List<String> skills, {
  String? searchQuery,
  List<String> absentAfterSearch = const [],
}) async {
  await _tapFirstAvailable(tester, [
    find.byIcon(Icons.build_rounded),
    find.textContaining('Skills'),
  ]);
  await _waitForText(tester, '选择 Skills');
  final trimmedQuery = searchQuery?.trim();
  if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
    for (final skill in skills) {
      await _waitForText(tester, skill, timeout: const Duration(seconds: 30));
    }
    for (final hidden in absentAfterSearch) {
      await _waitForText(tester, hidden, timeout: const Duration(seconds: 30));
    }
    final searchField = find.byType(TextField);
    await _waitForFinder(tester, searchField);
    await tester.ensureVisible(searchField.first);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(searchField.first, trimmedQuery);
    await tester.pump(const Duration(milliseconds: 500));
    for (final hidden in absentAfterSearch) {
      await _waitForAbsentText(
        tester,
        hidden,
        duration: const Duration(milliseconds: 800),
      );
    }
  }
  for (final skill in skills) {
    await _waitForText(tester, skill, timeout: const Duration(seconds: 30));
    await _tapFinder(tester, find.text(skill).first);
  }
  await _tapFinder(tester, find.byIcon(Icons.arrow_back_ios_new_rounded));
  await _waitForText(tester, '新建会话');
  for (final skill in skills) {
    await _waitForText(tester, skill);
  }
}

Future<void> _sendMessage(WidgetTester tester, String text) async {
  final input = find.widgetWithText(TextField, '输入消息...');
  await _waitForFinder(tester, input);
  await tester.enterText(input.first, text);
  await tester.pump(const Duration(milliseconds: 300));

  await _tapIcon(tester, 'send');
}

Future<void> _mockGatewayPush(Map<String, dynamic> step) async {
  if (_mockControlUrl.isEmpty) {
    throw StateError('CLAWKE_E2E_MOCK_CONTROL_URL is required');
  }
  final replies = step['replies'];
  if (replies is! List) {
    throw TestFailure('mock_gateway_push requires replies list');
  }

  final uri = Uri.parse('$_mockControlUrl/push');
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'conversation_id': step['conversation_id'],
        'replies': replies,
      }),
    );
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TestFailure('mock_gateway_push failed ${res.statusCode}: $body');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _deleteConversation(WidgetTester tester, String name) async {
  await _waitForText(tester, name);

  var opened = false;
  final candidateCount = find.textContaining(name).evaluate().length;
  for (var i = 0; i < candidateCount; i += 1) {
    final target = find.textContaining(name).at(i);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(target, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('删除会话').evaluate().isNotEmpty) {
      opened = true;
      break;
    }
  }
  if (!opened) {
    throw TestFailure('Timed out opening conversation menu for $name');
  }

  await _tapButtonText(tester, '删除会话', preferLast: true);
  await _waitForText(tester, '确定要删除此会话吗？');
  await _tapButtonText(tester, '删除', preferLast: true);
  await tester.pump(const Duration(seconds: 1));
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList();
}

Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _waitForFinder(tester, find.textContaining(text), timeout: timeout);
}

Future<void> _waitForAbsentText(
  WidgetTester tester,
  String text, {
  Duration duration = const Duration(milliseconds: 300),
}) async {
  await _expectFinderAbsentFor(
    tester,
    find.textContaining(text),
    duration: duration,
  );
}

Future<void> _waitForKey(
  WidgetTester tester,
  String key, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _waitForFinder(tester, find.byKey(ValueKey(key)), timeout: timeout);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await _tapFinder(tester, finder);
}

Future<void> _waitForIcon(
  WidgetTester tester,
  String icon, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _waitForFinder(tester, _findIcon(icon), timeout: timeout);
}

Future<void> _waitForAbsentIcon(
  WidgetTester tester,
  String icon, {
  Duration duration = const Duration(milliseconds: 300),
}) async {
  await _expectFinderAbsentFor(tester, _findIcon(icon), duration: duration);
}

Future<void> _waitForConversationUnread(
  WidgetTester tester, {
  required String name,
  required int count,
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _waitForFinder(
    tester,
    find.byKey(ValueKey('ui_e2e_conversation_unread_${name}_$count')),
    timeout: timeout,
  );
}

Future<void> _waitForConversationUnreadAbsent(
  WidgetTester tester, {
  required String name,
  required int count,
  required Duration duration,
}) async {
  await _expectFinderAbsentFor(
    tester,
    find.byKey(ValueKey('ui_e2e_conversation_unread_${name}_$count')),
    duration: duration,
  );
}

Future<void> _waitForNavUnread(
  WidgetTester tester, {
  required String label,
  required int count,
  Duration timeout = const Duration(seconds: 20),
}) async {
  await _waitForFinder(
    tester,
    find.byKey(ValueKey('ui_e2e_nav_unread_${label}_$count')),
    timeout: timeout,
  );
}

Future<void> _waitForNavUnreadAbsent(
  WidgetTester tester, {
  required String label,
  required int count,
  required Duration duration,
}) async {
  await _expectFinderAbsentFor(
    tester,
    find.byKey(ValueKey('ui_e2e_nav_unread_${label}_$count')),
    duration: duration,
  );
}

Future<void> _tapIcon(WidgetTester tester, String icon) async {
  await _tapFinder(tester, _findIcon(icon));
}

Finder _findIcon(String icon) {
  return find.byIcon(switch (icon) {
    'send' => Icons.send,
    'stop' => Icons.stop,
    'arrow_back' => Icons.arrow_back,
    'arrow_back_ios_new' => Icons.arrow_back_ios_new,
    'task_alt' => Icons.task_alt,
    _ => throw UnsupportedError('Unknown UI E2E icon: $icon'),
  });
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  required bool exact,
  bool preferLast = false,
}) async {
  await _tapFirstAvailable(tester, [
    exact ? find.text(text) : find.textContaining(text),
  ], preferLast: preferLast);
}

Future<void> _tapFilterChip(WidgetTester tester, String text) async {
  await _tapFirstAvailable(tester, [
    find.descendant(
      of: find.byType(FilterChip),
      matching: find.textContaining(text),
    ),
    find.descendant(
      of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
      matching: find.textContaining(text),
    ),
  ]);
}

Future<void> _tapButtonText(
  WidgetTester tester,
  String text, {
  bool preferLast = false,
}) async {
  await _tapFirstAvailable(tester, [
    find.widgetWithText(FilledButton, text),
    find.widgetWithText(OutlinedButton, text),
    find.widgetWithText(TextButton, text),
    find.text(text),
  ], preferLast: preferLast);
}

Future<void> _enterTextField(
  WidgetTester tester, {
  String? key,
  int? index,
  required String text,
  required bool formField,
}) async {
  final targetKey = key?.trim();
  final target = targetKey != null && targetKey.isNotEmpty
      ? find.byKey(ValueKey(targetKey))
      : (formField ? find.byType(TextFormField) : find.byType(TextField)).at(
          index ?? 0,
        );
  await _waitForFinder(tester, target);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(target, text);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapCardButton(
  WidgetTester tester, {
  required String cardText,
  required String buttonText,
}) async {
  final card = await _surfaceContainingText(tester, cardText);
  await _tapFirstAvailable(tester, [
    find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, buttonText),
    ),
    find.descendant(
      of: card,
      matching: find.widgetWithText(OutlinedButton, buttonText),
    ),
    find.descendant(
      of: card,
      matching: find.widgetWithText(TextButton, buttonText),
    ),
    find.descendant(of: card, matching: find.text(buttonText)),
  ]);
}

Future<void> _tapCardTooltip(
  WidgetTester tester, {
  required String cardText,
  required String tooltip,
}) async {
  final card = await _surfaceContainingText(tester, cardText);
  await _tapFinder(
    tester,
    find.descendant(of: card, matching: find.byTooltip(tooltip)),
  );
}

Future<void> _tapCardSwitch(WidgetTester tester, String cardText) async {
  final card = await _surfaceContainingText(tester, cardText);
  await _tapFinder(
    tester,
    find.descendant(of: card, matching: find.byType(Switch)),
  );
}

Future<Finder> _surfaceContainingText(WidgetTester tester, String text) async {
  final textFinder = find.textContaining(text);
  await _waitForFinder(tester, textFinder);
  for (final ancestorFinder in [
    find.byType(Card),
    find.byType(Material),
    find.byType(ListTile),
  ]) {
    final surface = find.ancestor(
      of: textFinder.first,
      matching: ancestorFinder,
    );
    final matchCount = surface.evaluate().length;
    if (matchCount > 0) return surface.at(matchCount - 1);
  }
  throw TestFailure('Timed out waiting for card-like surface containing $text');
}

Future<void> _tapFirstAvailable(
  WidgetTester tester,
  List<Finder> finders, {
  bool preferLast = false,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    for (final finder in finders) {
      final matches = finder.evaluate();
      if (matches.isEmpty) continue;
      await _tapFinder(tester, preferLast ? finder.last : finder.first);
      return;
    }
  }
  throw TestFailure('Timed out waiting for any of $finders');
}

Future<void> _tapFinder(WidgetTester tester, Finder finder) async {
  await _waitForFinder(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _waitForAbsentKey(
  WidgetTester tester,
  String key, {
  Duration duration = const Duration(milliseconds: 300),
}) async {
  await _expectFinderAbsentFor(
    tester,
    find.byKey(ValueKey(key)),
    duration: duration,
  );
}

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<void> _expectFinderAbsentFor(
  WidgetTester tester,
  Finder finder, {
  required Duration duration,
}) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      throw TestFailure('Expected $finder to stay absent for $duration');
    }
  }
}

Duration _stepDuration(Map<String, dynamic> step) {
  final durationMs = step['durationMs'] as int?;
  if (durationMs == null) return const Duration(milliseconds: 300);
  return Duration(milliseconds: durationMs);
}

Duration _stepTimeout(Map<String, dynamic> step) {
  final timeoutMs = step['timeoutMs'] as int?;
  if (timeoutMs == null) return const Duration(seconds: 20);
  return Duration(milliseconds: timeoutMs);
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String runDir,
  String name,
) async {
  try {
    await tester.pump(const Duration(milliseconds: 100));
    final boundary =
        boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('Root repaint boundary not found');
    }
    final image = await boundary
        .toImage(pixelRatio: 1)
        .timeout(const Duration(seconds: 3));
    final byteData = await image
        .toByteData(format: ui.ImageByteFormat.png)
        .timeout(const Duration(seconds: 3));
    if (byteData == null) {
      throw StateError('Screenshot byte data is null');
    }
    final bytes = byteData.buffer.asUint8List();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}-$name.png';
    final path = _tryWriteScreenshot(runDir, fileName, bytes);
    // 优先写入 runner 目录 — Prefer writing into the runner directory
    if (path != null) {
      // 截图路径供 runner 收集 — Screenshot path for runner collection
      // ignore: avoid_print
      print('E2E_SCREENSHOT:$path');
      return;
    }
    // 避开 macOS App 沙箱路径权限 — Avoid macOS app sandbox path permissions
    // ignore: avoid_print
    print('E2E_SCREENSHOT_BASE64:$fileName:${base64Encode(bytes)}');
  } catch (error) {
    // 截图失败不影响业务断言 — Screenshot failure must not mask test result
    // ignore: avoid_print
    print('E2E_SCREENSHOT_FAILED:$error');
  }
}

String? _tryWriteScreenshot(String runDir, String fileName, List<int> bytes) {
  if (runDir.isEmpty) return null;
  try {
    final dir = Directory('$runDir/screenshots');
    dir.createSync(recursive: true);
    final file = File('${dir.path}/$fileName');
    file.writeAsBytesSync(bytes);
    return file.path;
  } catch (_) {
    return null;
  }
}
