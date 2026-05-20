# SkillHub Refresh Skill Caches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SkillHub 安装完成后自动刷新本地 Skill 缓存，让技能管理页能立刻搜到刚安装的 Skill。

**Architecture:** 在客户端 `skillhub_provider.dart` 增加通用 helper `refreshSkillCaches()`，读取在线且支持 `skills` 的 gateway，并调用 `SkillCacheRepository.syncGateway()` 刷新缓存。`SkillHubController` 在安装完成状态到达时调用该 helper，不改 Server/Gateway 协议。

**Tech Stack:** Flutter, Riverpod, Drift-backed `SkillCacheRepository`, `flutter_test`

---

### Task 1: 缓存刷新测试

**Files:**
- Modify: `client/test/skillhub_provider_test.dart`

- [x] **Step 1: 增加 helper 覆盖测试**

在 `client/test/skillhub_provider_test.dart` 中新增 fake cache 和测试：

```dart
test('refreshSkillCaches syncs every online skills gateway', () async {
  final cache = _RecordingSkillCacheRepository();
  final container = ProviderContainer(
    overrides: [
      skillCacheRepositoryProvider.overrideWithValue(cache),
      onlineGatewayListProvider.overrideWith((ref) {
        return Stream.value(const [
          GatewayInfo(
            gatewayId: 'openclaw-local',
            displayName: 'OpenClaw',
            gatewayType: 'openclaw',
            status: GatewayConnectionStatus.online,
            capabilities: ['chat', 'skills'],
          ),
          GatewayInfo(
            gatewayId: 'chat-only',
            displayName: 'Chat Only',
            gatewayType: 'openclaw',
            status: GatewayConnectionStatus.online,
            capabilities: ['chat'],
          ),
          GatewayInfo(
            gatewayId: 'offline-hermes',
            displayName: 'Hermes',
            gatewayType: 'hermes',
            status: GatewayConnectionStatus.disconnected,
            capabilities: ['chat', 'skills'],
          ),
        ]);
      }),
      localeProvider.overrideWith((ref) {
        return LocaleNotifier(initialLocale: const Locale('zh'), loadFromPrefs: false);
      }),
    ],
  );
  addTearDown(container.dispose);

  await container.read(_refreshSkillCachesTestProvider.future);

  expect(cache.syncedGatewayIds, ['openclaw-local']);
  expect(cache.syncedLocales, ['zh']);
});
```

- [x] **Step 2: 增加安装完成触发测试**

在同一文件中新增测试：

```dart
test('installed SkillHub status refreshes local skill caches', () async {
  final api = _FakeSkillHubApiService(
    installResult: const SkillHubInstallResult(
      installId: 'skillhub_1',
      installed: false,
      status: 'accepted',
      message: '安装任务已提交',
    ),
  );
  final cache = _RecordingSkillCacheRepository();
  final container = _skillHubContainer(api, cache);
  addTearDown(container.dispose);

  await container.read(skillHubControllerProvider.notifier).load();
  final item = container.read(skillHubControllerProvider).items.single;
  await container.read(skillHubControllerProvider.notifier).install(item);

  container.read(skillHubControllerProvider.notifier).handleInstallStatus({
    'installId': 'skillhub_1',
    'status': 'downloading',
    'message': '正在从 ClawHub 下载',
  });
  await Future<void>.delayed(Duration.zero);
  expect(cache.syncedGatewayIds, isEmpty);

  container.read(skillHubControllerProvider.notifier).handleInstallStatus({
    'installId': 'skillhub_1',
    'status': 'installed',
    'message': '安装完成',
  });
  await Future<void>.delayed(Duration.zero);

  expect(cache.syncedGatewayIds, ['openclaw-local']);
});
```

- [x] **Step 3: 运行测试确认失败**

Run:

```bash
cd client && flutter test --no-pub test/skillhub_provider_test.dart --plain-name "refreshSkillCaches syncs every online skills gateway"
```

Expected: FAIL, `refreshSkillCaches` 或 `_refreshSkillCachesTestProvider` 未定义。

---

### Task 2: 实现 refreshSkillCaches

**Files:**
- Modify: `client/lib/providers/skillhub_provider.dart`
- Test: `client/test/skillhub_provider_test.dart`

- [x] **Step 1: 添加依赖和 helper**

在 `client/lib/providers/skillhub_provider.dart` 中添加依赖：

```dart
import 'dart:async';

import 'package:client/models/gateway_info.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/services/skills_api_service.dart';
```

添加 helper：

```dart
Future<void> refreshSkillCaches(Ref ref) async {
  final gateways =
      ref.read(onlineGatewayListProvider).valueOrNull ??
      await ref.read(onlineGatewayListProvider.future);
  final locale = ref.read(localeProvider)?.languageCode ?? 'en';
  final cache = ref.read(skillCacheRepositoryProvider);
  final skillGateways = gateways.where(
    (gateway) =>
        gateway.status == GatewayConnectionStatus.online &&
        gateway.supports('skills'),
  );

  await Future.wait(
    skillGateways.map((gateway) async {
      try {
        await cache.syncGateway(
          SkillScope(
            id: 'gateway:${gateway.gatewayId}',
            type: 'gateway',
            label: gateway.displayName,
            description: '${gateway.gatewayType} gateway',
            readonly: false,
            gatewayId: gateway.gatewayId,
          ),
          locale,
        );
      } catch (error) {
        debugPrint(
          '[SkillHub] refreshSkillCaches failed: gateway=${gateway.gatewayId} error=$error',
        );
      }
    }),
  );
}
```

- [x] **Step 2: 让 controller 持有 Ref 并触发刷新**

更新 provider 创建：

```dart
return SkillHubController(ref.watch(skillHubApiServiceProvider), ref: ref);
```

更新 controller：

```dart
class SkillHubController extends StateNotifier<SkillHubState> {
  SkillHubController(this._api, {Ref? ref})
    : _ref = ref,
      super(const SkillHubState());

  final SkillHubApiService _api;
  final Ref? _ref;

  void _refreshSkillCachesAfterChange() {
    final ref = _ref;
    if (ref == null) return;
    unawaited(refreshSkillCaches(ref));
  }
}
```

在同步安装结果和 websocket installed 状态处调用 `_refreshSkillCachesAfterChange()`。

- [x] **Step 3: 运行测试确认通过**

Run:

```bash
cd client && flutter test --no-pub test/skillhub_provider_test.dart
```

Expected: PASS。

---

### Task 3: WebSocket 状态回归

**Files:**
- Modify: `client/test/providers/chat_provider_thinking_test.dart`

- [x] **Step 1: 扩展已有 `skillhub_install_status` 测试**

给已有测试增加 cache/gateway override，并在 installed 后断言缓存刷新。示例断言：

```dart
expect(cache.syncedGatewayIds, ['openclaw-local']);
```

- [x] **Step 2: 运行聚焦测试**

Run:

```bash
cd client && flutter test --no-pub test/providers/chat_provider_thinking_test.dart --plain-name "skillhub_install_status 更新 SkillHub 安装状态"
```

Expected: PASS。

---

### Task 4: 验证和热部署

**Files:**
- Modify: `client/lib/providers/skillhub_provider.dart`
- Modify: `client/test/skillhub_provider_test.dart`
- Modify: `client/test/providers/chat_provider_thinking_test.dart`

- [x] **Step 1: 格式化**

Run:

```bash
cd client && dart format lib/providers/skillhub_provider.dart test/skillhub_provider_test.dart test/providers/chat_provider_thinking_test.dart
```

Expected: formatted files, no syntax error。

- [x] **Step 2: 静态检查**

Run:

```bash
cd client && dart analyze lib/providers/skillhub_provider.dart test/skillhub_provider_test.dart test/providers/chat_provider_thinking_test.dart
```

Expected: `No issues found!`

- [x] **Step 3: 热重载 macOS client**

确认当前 `flutter run` 属于本 worktree 后，向 flutter run PID 发送：

```bash
kill -SIGUSR1 <flutter-run-pid>
```

Expected log contains `Performing hot reload... Reloaded ... libraries`。
