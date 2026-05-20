# Multi Conversation Stream State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix chat flicker when multiple conversations receive streaming replies concurrently.

**Architecture:** Keep one `ChatScreen` viewport and move reply runtime state into a lightweight `conversationId -> runtime state` map. Delta events update only memory for their conversation; `text_done` is the only persistence point.

**Tech Stack:** Flutter, Riverpod, Drift, Flutter tests, Clawke UI E2E runner.

---

### Task 1: RED Provider Test

**Files:**
- Create: `client/test/providers/chat_provider_multi_conversation_stream_test.dart`

- [ ] Write a failing test that sends `text_delta` for conversation A, then B, while A remains selected.
- [ ] Verify current code fails because selected A's visible streaming state is replaced by B.

Run:

```bash
cd client
flutter test --no-pub test/providers/chat_provider_multi_conversation_stream_test.dart
```

Expected before implementation: FAIL.

### Task 2: RED UI E2E Case

**Files:**
- Modify: `client/integration_test/ui_e2e_app_test.dart`
- Create: `test/ui-e2e/test-cases/p0-multi-conversation-stream-isolation.json`

- [ ] Extend `mock_gateway_push` so a case may specify `conversation_name`.
- [ ] Add an E2E case that creates conversation B, streams B, then pushes A in the background and verifies B keeps its stop/streaming state.
- [ ] Verify current code fails before production changes.

Run:

```bash
./test/ui-e2e/tools/run.sh --case p0-multi-conversation-stream-isolation
```

Expected before implementation: FAIL after test harness support is in place.

### Task 3: Runtime State Isolation

**Files:**
- Modify: `client/lib/providers/chat_provider.dart`
- Modify: `client/lib/screens/chat_screen.dart`

- [ ] Add `ConversationRuntimeState` and a Riverpod controller keyed by `conversationId`.
- [ ] Move streaming text, streaming thinking, waiting state, active tool state, buffers, and flush timers to per-conversation state.
- [ ] Keep legacy global providers only as selected-conversation compatibility mirrors during this transition.
- [ ] Update `ChatScreen` to watch only the current conversation runtime state.

Run:

```bash
cd client
dart format lib/providers/chat_provider.dart lib/screens/chat_screen.dart
dart analyze lib/providers/chat_provider.dart lib/screens/chat_screen.dart
```

Expected after implementation: PASS.

### Task 4: GREEN Verification

**Files:**
- Modify tests only if expectations reference old global-only behavior.

- [ ] Run the new provider test and confirm GREEN.
- [ ] Run the new UI E2E case and confirm GREEN.
- [ ] Run existing related streaming tests.

Run:

```bash
cd client
flutter test --no-pub test/providers/chat_provider_multi_conversation_stream_test.dart
flutter test --no-pub test/providers/chat_provider_thinking_test.dart test/providers/chat_provider_disconnect_recovery_test.dart test/providers/chat_provider_tool_test.dart
cd ..
./test/ui-e2e/tools/run.sh --case p0-multi-conversation-stream-isolation
git diff --check
```

Expected after implementation: PASS.
