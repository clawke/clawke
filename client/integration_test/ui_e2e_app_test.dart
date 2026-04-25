import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const caseFile = String.fromEnvironment('CLAWKE_E2E_CASE_FILE');
  const caseJsonBase64 = String.fromEnvironment('CLAWKE_E2E_CASE_JSON_BASE64');
  const httpUrl = String.fromEnvironment('CLAWKE_E2E_HTTP_URL');
  const wsUrl = String.fromEnvironment('CLAWKE_E2E_WS_URL');
  const runDir = String.fromEnvironment('CLAWKE_E2E_RUN_DIR');

  group('UI E2E', () {
    testWidgets('runs case manifest from real Clawke UI', (tester) async {
      final testCase = _loadCase(
        caseFile: caseFile,
        caseJsonBase64: caseJsonBase64,
      );
      await _seedServerPrefs(httpUrl: httpUrl, wsUrl: wsUrl);

      await tester.pumpWidget(const ProviderScope(child: ClawkeApp()));
      await tester.pump(const Duration(seconds: 2));

      try {
        for (final step in (testCase['steps'] as List)) {
          await _runStep(tester, Map<String, dynamic>.from(step as Map));
        }
        for (final assertion in (testCase['assert'] as List)) {
          await _runAssert(tester, Map<String, dynamic>.from(assertion as Map));
        }
      } catch (_) {
        await _captureFailure(binding, runDir);
        rethrow;
      }
    });
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

Future<void> _seedServerPrefs({
  required String httpUrl,
  required String wsUrl,
}) async {
  if (httpUrl.isEmpty || wsUrl.isEmpty) {
    throw StateError('CLAWKE_E2E_HTTP_URL and CLAWKE_E2E_WS_URL are required');
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('clawke_http_url', httpUrl);
  await prefs.setString('clawke_ws_url', wsUrl);
  await prefs.setString('clawke_token', '');
  await prefs.setBool('clawke_logged_out', false);
}

Future<void> _runStep(WidgetTester tester, Map<String, dynamic> step) async {
  switch (step['action'] as String) {
    case 'launch_app':
      await tester.pump(const Duration(seconds: 2));
      return;
    case 'wait_for_text':
      await _waitForText(tester, step['text'] as String);
      return;
    case 'wait_for_absent_text':
      await _waitForAbsentText(
        tester,
        step['text'] as String,
        duration: _stepDuration(step),
      );
      return;
    case 'wait_for_key':
      await _waitForKey(tester, step['key'] as String);
      return;
    case 'wait_for_absent_key':
      await _waitForAbsentKey(
        tester,
        step['key'] as String,
        duration: _stepDuration(step),
      );
      return;
    case 'create_conversation':
      await _createConversation(tester, step['name'] as String);
      return;
    case 'send_message':
      await _sendMessage(tester, step['text'] as String);
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
  throw UnsupportedError('Unknown UI E2E assertion: $assertion');
}

Future<void> _createConversation(WidgetTester tester, String name) async {
  final addButton = find.byKey(
    const ValueKey('ui_e2e_new_conversation_button'),
  );
  await _waitForFinder(tester, addButton);
  await tester.tap(addButton.first);
  await tester.pump(const Duration(seconds: 1));

  final nameField = find.byKey(
    const ValueKey('ui_e2e_conversation_name_field'),
  );
  await _waitForFinder(tester, nameField);
  await tester.enterText(nameField, name);
  await tester.pump(const Duration(milliseconds: 300));

  final createButton = find.byKey(
    const ValueKey('ui_e2e_create_conversation_button'),
  );
  await tester.tap(createButton);
  await tester.pump(const Duration(seconds: 2));
  await _waitForText(tester, name);
}

Future<void> _sendMessage(WidgetTester tester, String text) async {
  final input = find.byKey(const ValueKey('ui_e2e_chat_input'));
  await _waitForFinder(tester, input);
  await tester.enterText(input, text);
  await tester.pump(const Duration(milliseconds: 300));

  final send = find.byKey(const ValueKey('ui_e2e_send_button'));
  await tester.tap(send);
  await tester.pump(const Duration(milliseconds: 300));
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

Future<void> _captureFailure(
  IntegrationTestWidgetsFlutterBinding binding,
  String runDir,
) async {
  if (runDir.isEmpty) return;
  final dir = Directory('$runDir/screenshots');
  try {
    dir.createSync(recursive: true);
    await binding.convertFlutterSurfaceToImage();
    final bytes = await binding.takeScreenshot('failure');
    File('${dir.path}/failure.png').writeAsBytesSync(bytes);
  } catch (_) {}
}
