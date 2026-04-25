# UI E2E System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first runnable Mock Gateway UI E2E loop for Clawke, starting with `p0-send-message`.

**Architecture:** A Node runner starts a test-isolated Clawke Server, starts a scripted Mock Gateway, then runs a real Flutter `integration_test` that drives the UI. The only mocked boundary is the Gateway; Client, Server, WebSocket, CUP translation, persistence, and UI rendering stay real.

**Tech Stack:** Node.js built-ins, Server `ws` dependency via `createRequire`, Flutter `integration_test`, JSON case manifests, local run artifacts under `test/ui-e2e/runs/`.

---

## File Structure

Create or modify these files:

- Create: `test/ui-e2e/tools/run.sh`  
  Shell entrypoint for manual execution.

- Create: `test/ui-e2e/tools/runner.mjs`  
  Orchestrates build, temp config, Server process, Mock Gateway process, Flutter integration test, artifact paths, and bug report generation.

- Create: `test/ui-e2e/tools/mock-gateway.mjs`  
  Scripted upstream Gateway that connects to `UPSTREAM_PORT`, identifies itself, receives real Server upstream messages, and replies from the case manifest.

- Create: `test/ui-e2e/test-cases/p0-send-message.json`  
  First persistent executable case.

- Create: `test/ui-e2e/templates/bug-report.md`  
  Markdown template used by the runner on failure.

- Create: `client/integration_test/ui_e2e_app_test.dart`  
  Real UI-driven Flutter integration test. It seeds only server connection prefs, pumps `ClawkeApp`, clicks UI, sends a message, and asserts visible output.

- Modify: `client/lib/screens/conversation_list_screen.dart`  
  Add stable key to the new conversation button.

- Modify: `client/lib/screens/conversation_settings_sheet.dart`  
  Add stable keys to the conversation name field and create button.

- Modify: `client/lib/screens/chat_screen.dart`  
  Add stable keys to the chat input and send/abort button.

- Modify: `test/ui-e2e/docs/ui-e2e-system-design.md`  
  Mark the first implementation target as `p0-send-message`.

---

## Task 1: Add Stable UI Keys

**Files:**
- Modify: `client/lib/screens/conversation_list_screen.dart`
- Modify: `client/lib/screens/conversation_settings_sheet.dart`
- Modify: `client/lib/screens/chat_screen.dart`
- Test: `client/integration_test/ui_e2e_app_test.dart` is added later and will use these keys.

- [ ] **Step 1: Add key to `NewConversationButton`**

In `client/lib/screens/conversation_list_screen.dart`, change the `IconButton` in `NewConversationButton.build()` to include a stable key:

```dart
return IconButton(
  key: const ValueKey('ui_e2e_new_conversation_button'),
  icon: Icon(Icons.add, size: iconSize),
  tooltip: context.l10n.newConversation,
  onPressed: accounts.isEmpty ? null : () => _onTap(context, ref, accounts),
  padding: EdgeInsets.zero,
  constraints: BoxConstraints(minWidth: minDim, minHeight: minDim),
);
```

- [ ] **Step 2: Add keys to conversation create UI**

In `client/lib/screens/conversation_settings_sheet.dart`, update the create button:

```dart
TextButton(
  key: const ValueKey('ui_e2e_create_conversation_button'),
  onPressed: _saving ? null : _save,
  child: Text(
    context.l10n.create,
    style: TextStyle(
      color: colorScheme.primary,
      fontWeight: FontWeight.w600,
    ),
  ),
),
```

In `_buildNameInput()`, update the `TextField`:

```dart
TextField(
  key: const ValueKey('ui_e2e_conversation_name_field'),
  controller: _nameController,
  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
  decoration: InputDecoration(
    hintText: context.l10n.enterConversationName,
    hintStyle: TextStyle(
      color: colorScheme.onSurface.withOpacity(0.3),
    ),
    border: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
  ),
),
```

- [ ] **Step 3: Add keys to chat input and send button**

In `client/lib/screens/chat_screen.dart`, update the message input `TextField`:

```dart
TextField(
  key: const ValueKey('ui_e2e_chat_input'),
  focusNode: _focusNode,
  controller: _controller,
  enabled: connected,
  maxLines: 5,
  minLines: 1,
  textInputAction: TextInputAction.newline,
  decoration: InputDecoration(
    hintText: connected
        ? context.l10n.typeMessage
        : context.l10n.notConnected,
    filled: true,
    fillColor: colorScheme.surfaceContainerLowest,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: colorScheme.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
  ),
),
```

Update the `IconButton.filled` used for send/abort:

```dart
return IconButton.filled(
  key: ValueKey(isMyStreaming ? 'ui_e2e_abort_button' : 'ui_e2e_send_button'),
  onPressed: connected
      ? (isMyStreaming
          ? () => ref.read(wsMessageHandlerProvider).sendAbort()
          : _handleSend)
      : null,
  icon: Icon(isMyStreaming ? Icons.stop : Icons.send),
  style: isMyStreaming
      ? IconButton.styleFrom(backgroundColor: colorScheme.error)
      : null,
);
```

- [ ] **Step 4: Run focused Flutter tests**

Run:

```bash
cd client
flutter test test/screens/chat_screen_test.dart test/screens/conversation_list_screen_test.dart
```

Expected: existing tests pass. If either file does not exist in the clean worktree, run:

```bash
cd client
flutter test test/screens/chat_screen_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/screens/conversation_list_screen.dart client/lib/screens/conversation_settings_sheet.dart client/lib/screens/chat_screen.dart
git commit -m "test(client): add stable ui e2e keys"
```

---

## Task 2: Add Persistent Case and Report Template

**Files:**
- Create: `test/ui-e2e/test-cases/p0-send-message.json`
- Create: `test/ui-e2e/templates/bug-report.md`
- Modify: `test/ui-e2e/docs/ui-e2e-system-design.md`

- [ ] **Step 1: Create the first case manifest**

Create `test/ui-e2e/test-cases/p0-send-message.json`:

```json
{
  "id": "p0-send-message",
  "title": "Send message and render streamed mock gateway reply",
  "tags": ["p0", "chat", "streaming", "ui"],
  "setup": {
    "serverMode": "openclaw",
    "accountId": "e2e_mock",
    "agentName": "E2E Mock Gateway",
    "httpPort": 18780,
    "upstreamPort": 18766,
    "mediaPort": 18781
  },
  "steps": [
    { "action": "launch_app" },
    { "action": "wait_for_text", "text": "Clawke" },
    { "action": "create_conversation", "name": "E2E P0 Send Message" },
    { "action": "send_message", "text": "你好 Clawke" },
    { "action": "wait_for_text", "text": "这是 Mock Gateway 的稳定回复" }
  ],
  "mockGateway": {
    "onUserMessage": {
      "contains": "你好 Clawke",
      "replies": [
        {
          "type": "agent_text_delta",
          "message_id": "agent_msg_p0_send_1",
          "delta": "这是 Mock Gateway 的"
        },
        {
          "type": "agent_text_delta",
          "message_id": "agent_msg_p0_send_1",
          "delta": "稳定回复"
        },
        {
          "type": "agent_text_done",
          "message_id": "agent_msg_p0_send_1",
          "fullText": "这是 Mock Gateway 的稳定回复"
        }
      ]
    }
  },
  "assert": [
    { "uiTextVisible": "你好 Clawke" },
    { "uiTextVisible": "这是 Mock Gateway 的稳定回复" }
  ]
}
```

- [ ] **Step 2: Create bug report template**

Create `test/ui-e2e/templates/bug-report.md`:

```markdown
# UI E2E Bug: {{case_id}}

## Summary

{{summary}}

## Case

- id: {{case_id}}
- title: {{case_title}}
- run_id: {{run_id}}
- branch: {{branch}}

## Expected

{{expected}}

## Actual

{{actual}}

## Repro Steps

{{repro_steps}}

## Artifacts

- run_dir: {{run_dir}}
- server_log: {{server_log}}
- client_log: {{client_log}}
- mock_gateway_log: {{mock_gateway_log}}
- screenshot_dir: {{screenshot_dir}}
```

- [ ] **Step 3: Verify design doc names the chosen first case**

Confirm `test/ui-e2e/docs/ui-e2e-system-design.md` contains:

```markdown
第一条落地用例固定为 `test/ui-e2e/test-cases/p0-send-message.json`。
```

- [ ] **Step 4: Validate JSON**

Run:

```bash
node -e "JSON.parse(require('node:fs').readFileSync('test/ui-e2e/test-cases/p0-send-message.json','utf8')); console.log('ok')"
```

Expected:

```text
ok
```

- [ ] **Step 5: Commit**

```bash
git add test/ui-e2e/test-cases/p0-send-message.json test/ui-e2e/templates/bug-report.md test/ui-e2e/docs/ui-e2e-system-design.md
git commit -m "test(ui-e2e): add p0 send message case"
```

---

## Task 3: Add Scripted Mock Gateway

**Files:**
- Create: `test/ui-e2e/tools/mock-gateway.mjs`
- Test: manual run through Task 5 runner.

- [ ] **Step 1: Create `mock-gateway.mjs`**

```js
#!/usr/bin/env node
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const requireFromServer = createRequire(new URL('../../../server/package.json', import.meta.url));
const WebSocket = requireFromServer('ws');

const args = parseArgs(process.argv.slice(2));
const casePath = required(args, 'case');
const upstreamUrl = required(args, 'upstream-url');
const logPath = required(args, 'log');
const testCase = JSON.parse(fs.readFileSync(casePath, 'utf8'));
const setup = testCase.setup || {};
const accountId = setup.accountId || 'e2e_mock';
const agentName = setup.agentName || 'E2E Mock Gateway';

fs.mkdirSync(path.dirname(logPath), { recursive: true });
const logStream = fs.createWriteStream(logPath, { flags: 'a' });

function log(message) {
  const line = `[mock-gateway] ${new Date().toISOString()} ${message}`;
  console.log(line);
  logStream.write(`${line}\n`);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 2) {
    out[argv[i].replace(/^--/, '')] = argv[i + 1];
  }
  return out;
}

function required(map, key) {
  if (!map[key]) {
    console.error(`Missing --${key}`);
    process.exit(2);
  }
  return map[key];
}

function withConversation(reply, incoming) {
  return {
    ...reply,
    conversation_id: incoming.conversation_id || accountId,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function sendReplies(ws, incoming) {
  const rule = testCase.mockGateway?.onUserMessage;
  if (!rule) return;
  const text = incoming.text || '';
  if (rule.contains && !text.includes(rule.contains)) {
    log(`ignored chat text="${text}"`);
    return;
  }

  for (const reply of rule.replies || []) {
    await sleep(reply.delayMs || 40);
    const payload = withConversation(reply, incoming);
    log(`send ${JSON.stringify(payload)}`);
    ws.send(JSON.stringify(payload));
  }
}

function connect() {
  log(`connecting ${upstreamUrl}`);
  const ws = new WebSocket(upstreamUrl);

  ws.on('open', () => {
    const identify = { type: 'identify', accountId, agentName };
    log(`identify ${JSON.stringify(identify)}`);
    ws.send(JSON.stringify(identify));
  });

  ws.on('message', async (raw) => {
    const text = raw.toString();
    log(`recv ${text}`);
    let msg;
    try {
      msg = JSON.parse(text);
    } catch {
      log('invalid json ignored');
      return;
    }
    if (msg.type === 'chat') {
      await sendReplies(ws, msg);
    }
  });

  ws.on('close', () => {
    log('closed');
    process.exit(0);
  });

  ws.on('error', (err) => {
    log(`error ${err.message}`);
    process.exit(1);
  });
}

process.on('SIGTERM', () => {
  log('SIGTERM');
  process.exit(0);
});

connect();
```

- [ ] **Step 2: Make executable**

Run:

```bash
chmod +x test/ui-e2e/tools/mock-gateway.mjs
```

- [ ] **Step 3: Commit**

```bash
git add test/ui-e2e/tools/mock-gateway.mjs
git commit -m "test(ui-e2e): add scripted mock gateway"
```

---

## Task 4: Add Flutter UI E2E Test

**Files:**
- Create: `client/integration_test/ui_e2e_app_test.dart`

- [ ] **Step 1: Create generic Flutter E2E test**

Create `client/integration_test/ui_e2e_app_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/main.dart';

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const caseFile = String.fromEnvironment('CLAWKE_E2E_CASE_FILE');
  const httpUrl = String.fromEnvironment('CLAWKE_E2E_HTTP_URL');
  const wsUrl = String.fromEnvironment('CLAWKE_E2E_WS_URL');
  const runDir = String.fromEnvironment('CLAWKE_E2E_RUN_DIR');

  group('UI E2E', () {
    testWidgets('runs case manifest from real Clawke UI', (tester) async {
      final testCase = _loadCase(caseFile);
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

Map<String, dynamic> _loadCase(String path) {
  if (path.isEmpty) {
    throw StateError('CLAWKE_E2E_CASE_FILE is required');
  }
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
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
    case 'wait_for_text':
      await _waitForText(tester, step['text'] as String);
    case 'create_conversation':
      await _createConversation(tester, step['name'] as String);
    case 'send_message':
      await _sendMessage(tester, step['text'] as String);
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
  final addButton = find.byKey(const ValueKey('ui_e2e_new_conversation_button'));
  await _waitForFinder(tester, addButton);
  await tester.tap(addButton.first);
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final nameField = find.byKey(const ValueKey('ui_e2e_conversation_name_field'));
  await _waitForFinder(tester, nameField);
  await tester.enterText(nameField, name);
  await tester.pump(const Duration(milliseconds: 300));

  final createButton =
      find.byKey(const ValueKey('ui_e2e_create_conversation_button'));
  await tester.tap(createButton);
  await tester.pumpAndSettle(const Duration(seconds: 2));
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

Future<void> _captureFailure(
  IntegrationTestWidgetsFlutterBinding binding,
  String runDir,
) async {
  if (runDir.isEmpty) return;
  final dir = Directory('$runDir/screenshots');
  dir.createSync(recursive: true);
  try {
    await binding.convertFlutterSurfaceToImage();
    final bytes = await binding.takeScreenshot('failure');
    File('${dir.path}/failure.png').writeAsBytesSync(bytes);
  } catch (_) {
    File('${dir.path}/screenshot-error.txt')
        .writeAsStringSync('Failed to capture screenshot');
  }
}
```

- [ ] **Step 2: Run the Flutter test without services to confirm it fails for missing Server**

Run:

```bash
cd client
flutter test integration_test/ui_e2e_app_test.dart -d macos \
  --dart-define=CLAWKE_E2E_CASE_FILE="$(pwd)/../test/ui-e2e/test-cases/p0-send-message.json" \
  --dart-define=CLAWKE_E2E_HTTP_URL=http://127.0.0.1:18780 \
  --dart-define=CLAWKE_E2E_WS_URL=ws://127.0.0.1:18780/ws \
  --dart-define=CLAWKE_E2E_RUN_DIR="$(pwd)/../test/ui-e2e/runs/manual-probe"
```

Expected: FAIL waiting for connection-dependent UI. This confirms the test is not mocked internally.

- [ ] **Step 3: Commit**

```bash
git add client/integration_test/ui_e2e_app_test.dart
git commit -m "test(client): add ui e2e app harness"
```

---

## Task 5: Add Node Runner

**Files:**
- Create: `test/ui-e2e/tools/runner.mjs`
- Create: `test/ui-e2e/tools/run.sh`

- [ ] **Step 1: Create `runner.mjs`**

```js
#!/usr/bin/env node
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const root = path.resolve(new URL('../../..', import.meta.url).pathname);
const args = parseArgs(process.argv.slice(2));
const caseId = args.case || 'p0-send-message';
const casePath = path.join(root, 'test', 'ui-e2e', 'test-cases', `${caseId}.json`);
const testCase = JSON.parse(fs.readFileSync(casePath, 'utf8'));
const setup = testCase.setup || {};
const runId = new Date().toISOString().replace(/[:.]/g, '-');
const runDir = path.join(root, 'test', 'ui-e2e', 'runs', `${runId}-${caseId}`);
const bugDir = path.join(root, 'test', 'ui-e2e', 'bug-reports');
const httpPort = Number(setup.httpPort || 18780);
const upstreamPort = Number(setup.upstreamPort || 18766);
const mediaPort = Number(setup.mediaPort || 18781);

fs.mkdirSync(runDir, { recursive: true });
fs.mkdirSync(path.join(runDir, 'server-home'), { recursive: true });
fs.mkdirSync(path.join(runDir, 'screenshots'), { recursive: true });
fs.mkdirSync(bugDir, { recursive: true });

const logs = {
  server: path.join(runDir, 'server.log'),
  client: path.join(runDir, 'client.log'),
  mockGateway: path.join(runDir, 'mock-gateway.log'),
};

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const item = argv[i];
    if (!item.startsWith('--')) continue;
    const key = item.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      out[key] = true;
    } else {
      out[key] = next;
      i += 1;
    }
  }
  return out;
}

function writeTestConfig() {
  const configPath = path.join(runDir, 'server-home', 'clawke.json');
  const config = {
    server: {
      mode: 'openclaw',
      httpPort,
      upstreamPort,
      mediaPort,
      fastMode: true,
      logLevel: 'info'
    },
    openclaw: {
      sharedFs: false,
      mediaBaseUrl: `http://127.0.0.1:${mediaPort}`
    },
    relay: {
      enable: false,
      token: '',
      relayUrl: '',
      serverAddr: '',
      serverPort: 7000
    }
  };
  fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
}

function openLog(file) {
  return fs.openSync(file, 'a');
}

function spawnLogged(command, argv, options, logFile) {
  const fd = openLog(logFile);
  const child = spawn(command, argv, {
    ...options,
    stdio: ['ignore', fd, fd],
  });
  child.on('exit', () => fs.closeSync(fd));
  return child;
}

async function waitForHealth() {
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (await httpOk(`http://127.0.0.1:${httpPort}/health`)) return;
    await sleep(250);
  }
  throw new Error(`Server health check timed out on port ${httpPort}`);
}

function httpOk(url) {
  return new Promise((resolve) => {
    const req = http.get(url, (res) => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(1000, () => {
      req.destroy();
      resolve(false);
    });
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildServer() {
  const result = spawnSync('npm', ['run', 'build'], {
    cwd: path.join(root, 'server'),
    stdio: 'inherit',
  });
  if (result.status !== 0) {
    throw new Error('server build failed');
  }
}

function writeBugReport(error) {
  const templatePath = path.join(root, 'test', 'ui-e2e', 'templates', 'bug-report.md');
  const template = fs.readFileSync(templatePath, 'utf8');
  const branch = spawnSync('git', ['branch', '--show-current'], {
    cwd: root,
    encoding: 'utf8',
  }).stdout.trim();
  const report = template
    .replaceAll('{{case_id}}', testCase.id)
    .replaceAll('{{case_title}}', testCase.title)
    .replaceAll('{{run_id}}', runId)
    .replaceAll('{{branch}}', branch)
    .replaceAll('{{summary}}', `Case failed: ${testCase.title}`)
    .replaceAll('{{expected}}', JSON.stringify(testCase.assert, null, 2))
    .replaceAll('{{actual}}', error.message || String(error))
    .replaceAll('{{repro_steps}}', (testCase.steps || []).map((step, index) => `${index + 1}. ${JSON.stringify(step)}`).join('\n'))
    .replaceAll('{{run_dir}}', runDir)
    .replaceAll('{{server_log}}', logs.server)
    .replaceAll('{{client_log}}', logs.client)
    .replaceAll('{{mock_gateway_log}}', logs.mockGateway)
    .replaceAll('{{screenshot_dir}}', path.join(runDir, 'screenshots'));
  const reportPath = path.join(bugDir, `${runId}-${testCase.id}.md`);
  fs.writeFileSync(reportPath, report);
  return reportPath;
}

async function main() {
  writeTestConfig();
  buildServer();

  const children = [];
  try {
    const server = spawnLogged('node', ['dist/index.js'], {
      cwd: path.join(root, 'server'),
      env: {
        ...process.env,
        CLAWKE_DATA_DIR: path.join(runDir, 'server-home'),
        MODE: 'openclaw',
        NODE_TEST: '1',
      },
    }, logs.server);
    children.push(server);

    await waitForHealth();

    const mockGateway = spawnLogged('node', [
      path.join(root, 'test', 'ui-e2e', 'tools', 'mock-gateway.mjs'),
      '--case', casePath,
      '--upstream-url', `ws://127.0.0.1:${upstreamPort}`,
      '--log', logs.mockGateway,
    ], { cwd: root }, logs.mockGateway);
    children.push(mockGateway);

    await sleep(1000);

    const flutterArgs = [
      'test',
      'integration_test/ui_e2e_app_test.dart',
      '-d',
      'macos',
      `--dart-define=CLAWKE_E2E_CASE_FILE=${casePath}`,
      `--dart-define=CLAWKE_E2E_HTTP_URL=http://127.0.0.1:${httpPort}`,
      `--dart-define=CLAWKE_E2E_WS_URL=ws://127.0.0.1:${httpPort}/ws`,
      `--dart-define=CLAWKE_E2E_RUN_DIR=${runDir}`,
    ];
    const flutter = spawnSync('flutter', flutterArgs, {
      cwd: path.join(root, 'client'),
      encoding: 'utf8',
      maxBuffer: 1024 * 1024 * 20,
    });
    fs.writeFileSync(logs.client, `${flutter.stdout || ''}\n${flutter.stderr || ''}`);
    if (flutter.status !== 0) {
      throw new Error(`flutter test failed with status ${flutter.status}`);
    }

    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: true,
      case_id: testCase.id,
      run_id: runId,
      run_dir: runDir,
    }, null, 2));
    console.log(`PASS ${testCase.id}`);
    console.log(`Artifacts: ${runDir}`);
  } catch (error) {
    fs.writeFileSync(path.join(runDir, 'result.json'), JSON.stringify({
      ok: false,
      case_id: testCase.id,
      run_id: runId,
      error: error.message || String(error),
      run_dir: runDir,
    }, null, 2));
    const reportPath = writeBugReport(error);
    console.error(`FAIL ${testCase.id}`);
    console.error(`Bug report: ${reportPath}`);
    process.exitCode = 1;
  } finally {
    for (const child of children.reverse()) {
      if (!child.killed) child.kill('SIGTERM');
    }
  }
}

main();
```

- [ ] **Step 2: Create shell entrypoint**

Create `test/ui-e2e/tools/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node "$SCRIPT_DIR/runner.mjs" "$@"
```

- [ ] **Step 3: Make scripts executable**

Run:

```bash
chmod +x test/ui-e2e/tools/run.sh test/ui-e2e/tools/runner.mjs
```

- [ ] **Step 4: Commit**

```bash
git add test/ui-e2e/tools/runner.mjs test/ui-e2e/tools/run.sh
git commit -m "test(ui-e2e): add manual e2e runner"
```

---

## Task 6: Run the First Full UI E2E Loop

**Files:**
- Runtime output only: `test/ui-e2e/runs/`
- Runtime failure reports only: `test/ui-e2e/bug-reports/`

- [ ] **Step 1: Run the suite**

Run:

```bash
./test/ui-e2e/tools/run.sh --case p0-send-message
```

Expected success output:

```text
PASS p0-send-message
Artifacts: /Users/samy/MyProject/ai/clawke/.worktrees/ui-e2e-system/test/ui-e2e/runs/<run_id>-p0-send-message
```

- [ ] **Step 2: If it fails, inspect generated report**

Run:

```bash
ls -t test/ui-e2e/bug-reports | head -1
```

Expected on failure: a markdown report exists and links server/client/mock-gateway logs.

- [ ] **Step 3: Fix only confirmed failures**

Use logs from:

```text
test/ui-e2e/runs/<run_id>-p0-send-message/server.log
test/ui-e2e/runs/<run_id>-p0-send-message/client.log
test/ui-e2e/runs/<run_id>-p0-send-message/mock-gateway.log
```

Do not change business logic from guesses. If root cause is unclear, add targeted diagnostic logs first, rerun, then fix.

- [ ] **Step 4: Commit any fixes in the first-loop file set**

Use a focused commit message matching the actual fix. For first-loop stabilization, the expected editable file set is:

```bash
git add client/integration_test/ui_e2e_app_test.dart \
  client/lib/screens/chat_screen.dart \
  client/lib/screens/conversation_list_screen.dart \
  client/lib/screens/conversation_settings_sheet.dart \
  test/ui-e2e/tools/runner.mjs \
  test/ui-e2e/tools/mock-gateway.mjs \
  test/ui-e2e/tools/run.sh \
  test/ui-e2e/test-cases/p0-send-message.json \
  test/ui-e2e/templates/bug-report.md
git commit -m "fix(ui-e2e): stabilize p0 send message flow"
```

---

## Task 7: Add Documentation for Running and Writing Cases

**Files:**
- Create: `test/ui-e2e/docs/README.md`

- [ ] **Step 1: Create README**

Create `test/ui-e2e/docs/README.md`:

````markdown
# UI E2E

This directory stores Clawke's UI-driven system integration tests.

## Run

```bash
./test/ui-e2e/tools/run.sh --case p0-send-message
```

## What Is Real

- Flutter UI
- Clawke Server
- WebSocket transport
- CUP parsing and rendering
- Server message persistence in isolated test DB/data

## What Is Mocked

- Gateway only
- LLM output only through scripted Gateway replies

## Case Files

Cases live in `test/ui-e2e/test-cases/`.

Use JSON for now to avoid extra parser dependencies.

## Run Artifacts

Runtime output is local and ignored by Git:

- `test/ui-e2e/runs/`
- `test/ui-e2e/bug-reports/`
````

- [ ] **Step 2: Commit**

```bash
git add test/ui-e2e/docs/README.md
git commit -m "docs(ui-e2e): document manual e2e runner"
```

---

## Next Plan After This Loop

After `p0-send-message` is green, write a separate small plan for the next P0 cases:

- `p0-code-editor-action`
- `p0-gateway-reconnect`
- `p0-abort`

The next plan must first decide whether generic CUP `user_action` events should be asserted from Server logs or forwarded upstream to the Mock Gateway. Current Server behavior logs unknown actions through `ActionRouter`; it does not forward generic remote actions upstream.

---

## Self-Review

- Spec coverage: the plan implements the approved Mock Gateway UI E2E first loop, persistent case assets, local run artifacts, and bug reports.
- Deferred scope is explicit: PRD generation, CI, Mock Agent Full E2E, Local LLM Smoke, and Remote LLM Smoke are not part of the first loop.
- Mock boundary is correct: Gateway only.
- Data isolation is explicit: runner sets `CLAWKE_DATA_DIR` under `test/ui-e2e/runs/<run_id>/server-home` and `NODE_TEST=1`.
- First p0 case is concrete and executable.
