# Gateway Resource Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make conversation settings use the same DB-first cache pattern as Skill Center for gateway skills and gateway models.

**Architecture:** Gateway remains the source of truth. Server persists gateway model snapshots in SQLite so Server restarts do not force a slow model lookup, while skill list truth still comes from Gateway. Client stores gateway resources in Drift per `userId + gatewayId`, renders from DB first, then refreshes asynchronously over HTTP and updates DB.

**Tech Stack:** Node.js/Express server routes with `node:test`; Flutter, Riverpod, Drift local DB, `flutter_test`.

---

## Scope

In scope:

- Add `GET /api/models?gateway_id=<id>&refresh=1`.
- Add Server-side SQLite snapshot cache for gateway models.
- Mark `/api/config/models` and `/api/config/skills` as deprecated compatibility endpoints.
- Add Client-side `model_cache` with DAO and repository.
- Reuse existing Client-side `skill_cache` for conversation settings skills.
- Update conversation settings model/skill loading to DB-first plus async refresh.
- Preserve selected stale model/skill values in UI instead of silently deleting them.

Out of scope:

- Server DB caching for raw skill lists.
- Removing deprecated `/api/config/*` endpoints.
- Reworking Skill Center UI.
- Adding a full model management page.

## File Map

Server:

- Modify `server/src/routes/config-routes.ts`
  - Add shared model list helper.
  - Add deprecated comments on `/api/config/models` and `/api/config/skills` handlers.
  - Read/write gateway model snapshots through Server SQLite cache.
- Create `server/src/store/gateway-model-cache-store.ts`
  - Store model snapshots by `gateway_id + model_id`.
- Modify `server/src/http-server.ts`
  - Register `GET /api/models`.
  - Add `/api/models` to root endpoint metadata.
- Test `server/test/model-routes.test.js`
  - Verify `/api/models` accepts `gateway_id`.
  - Verify `refresh=1` bypasses Server DB snapshot cache.
  - Verify `/api/config/models` remains compatible.

Client database and data layer:

- Create `client/lib/data/database/tables/model_cache.drift`
  - Store models by `user_id + gateway_id + model_id`.
- Modify `client/lib/data/database/app_database.dart`
  - Include `model_cache.drift`.
  - Bump schema version from `10` to `11`.
  - Create table on upgrade from earlier versions.
- Create `client/lib/data/database/dao/model_cache_dao.dart`
  - Provide `watchModels`, `getModels`, `upsertModels`, `deleteMissing`.
- Create `client/lib/models/gateway_model.dart`
  - Minimal model representation for UI and cache.
- Create `client/lib/services/models_api_service.dart`
  - Call `GET /api/models`.
- Create `client/lib/data/repositories/model_cache_repository.dart`
  - DB-first model cache with remote sync.
- Modify `client/lib/providers/database_providers.dart`
  - Add model DAO, service, and repository providers.

Client UI:

- Modify `client/lib/screens/conversation_settings_sheet.dart`
  - Remove settings-page skills list dependency on `ConfigApiService.getSkills`.
  - Load models from `ModelCacheRepository`.
  - Load skills from `SkillCacheRepository`.
  - Show cached values first, then update after sync.
  - Preserve selected stale values with a visible stale label.

Client tests:

- Create `client/test/providers/model_cache_repository_test.dart`
  - Validate cache read and remote sync.
- Modify or create `client/test/conversation_settings_sheet_test.dart`
  - Validate DB-first models.
  - Validate DB-first skills.
  - Validate stale selected values remain visible.

---

## Task 1: Server `/api/models` Resource Endpoint

**Files:**

- Modify: `server/src/routes/config-routes.ts`
- Modify: `server/src/http-server.ts`
- Test: `server/test/model-routes.test.js`

- [x] **Step 1: Write the failing Server route test**

Create `server/test/model-routes.test.js` with this test shape:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {
  initConfigRoutes,
  listModels,
  getModels,
} from '../dist/routes/config-routes.js';

function buildApp() {
  const app = express();
  app.get('/api/models', listModels);
  app.get('/api/config/models', getModels);
  return app;
}

async function withServer(app, fn) {
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  const address = server.address();
  assert.equal(typeof address, 'object');
  const baseUrl = `http://127.0.0.1:${address.port}`;
  try {
    await fn(baseUrl);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  }
}

async function getJson(baseUrl, path) {
  const response = await fetch(`${baseUrl}${path}`);
  assert.equal(response.status, 200);
  return response.json();
}

test('GET /api/models queries models by gateway_id and caches the result', async () => {
  let calls = 0;
  initConfigRoutes({
    configStore: { get: () => null, set: () => {}, delete: () => {} },
    queryModels: async (gatewayId) => {
      calls += 1;
      assert.equal(gatewayId, 'hermes');
      return [`model-${calls}`];
    },
    querySkills: async () => [],
  });
  const app = buildApp();

  await withServer(app, async (baseUrl) => {
    const first = await getJson(baseUrl, '/api/models?gateway_id=hermes');
    assert.deepEqual(first.models, ['model-1']);

    const second = await getJson(baseUrl, '/api/models?gateway_id=hermes');
    assert.deepEqual(second.models, ['model-1']);
    assert.equal(calls, 1);
  });
});

test('GET /api/models refresh=1 bypasses model memory cache', async () => {
  let calls = 0;
  initConfigRoutes({
    configStore: { get: () => null, set: () => {}, delete: () => {} },
    queryModels: async () => {
      calls += 1;
      return [`model-${calls}`];
    },
    querySkills: async () => [],
  });
  const app = buildApp();

  await withServer(app, async (baseUrl) => {
    await getJson(baseUrl, '/api/models?gateway_id=hermes');
    const refreshed = await getJson(baseUrl, '/api/models?gateway_id=hermes&refresh=1');

    assert.deepEqual(refreshed.models, ['model-2']);
    assert.equal(calls, 2);
  });
});

test('deprecated GET /api/config/models remains compatible with account_id', async () => {
  initConfigRoutes({
    configStore: { get: () => null, set: () => {}, delete: () => {} },
    queryModels: async (gatewayId) => {
      assert.equal(gatewayId, 'hermes');
      return ['claude-sonnet'];
    },
    querySkills: async () => [],
  });
  const app = buildApp();

  await withServer(app, async (baseUrl) => {
    const response = await getJson(baseUrl, '/api/config/models?account_id=hermes&refresh=1');
    assert.deepEqual(response.models, ['claude-sonnet']);
  });
});
```

- [x] **Step 2: Run the failing Server test**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/server
npm run build
node --test test/model-routes.test.js
```

Expected before implementation:

```text
SyntaxError or export error for listModels
```

- [x] **Step 3: Implement shared model route logic**

In `server/src/routes/config-routes.ts`, extract a common model response helper and add the new resource handler:

```ts
export async function listModels(req: Request, res: Response): Promise<void> {
  await respondModels(req, res);
}

// Deprecated compatibility endpoint.
// 中文：兼容旧版会话设置页的模型列表接口，新代码使用 /api/models。
// English: Compatibility endpoint for legacy conversation settings model list. New code should use /api/models.
export async function getModels(req: Request, res: Response): Promise<void> {
  await respondModels(req, res);
}

async function respondModels(req: Request, res: Response): Promise<void> {
  try {
    const gatewayId = resolveGatewayId(req);
    if (!gatewayId) {
      res.status(400).json({ error: 'gateway_id is required' });
      return;
    }

    const forceRefresh = req.query.refresh === '1' || req.query.refresh === 'true';
    const cached = modelCache.get(gatewayId);
    if (!forceRefresh && cached && Date.now() < cached.expiresAt) {
      res.json({ models: cached.models });
      return;
    }

    const models = queryModelsFunc ? await queryModelsFunc(gatewayId) : [];
    if (models.length > 0) {
      modelCache.set(gatewayId, { models, expiresAt: Date.now() + MODEL_CACHE_TTL });
    }
    res.json({ models });
  } catch (err: any) {
    console.error('[ConfigAPI] getModels error:', err.message);
    res.status(500).json({ error: err.message });
  }
}

function resolveGatewayId(req: Request): string {
  return (req.query.gateway_id as string) || (req.query.account_id as string) || '';
}
```

Also add a deprecation comment before `getSkills`:

```ts
// Deprecated compatibility endpoint.
// 中文：兼容旧版会话设置页的 Skills 列表接口，新代码使用 /api/skills 并走客户端本地缓存。
// English: Compatibility endpoint for legacy conversation settings skills list. New code should use /api/skills with client-side cache.
export async function getSkills(req: Request, res: Response): Promise<void> {
```

In `server/src/http-server.ts`, import and register `listModels`:

```ts
import { getModels, getSkills, getConvConfig, putConvConfig, listModels } from './routes/config-routes.js';
```

Add:

```ts
app.get('/api/models', listModels as any);
```

Add `/api/models` to the root endpoint arrays.

- [x] **Step 4: Run Server tests**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/server
npm run build
node --test test/model-routes.test.js
```

Expected:

```text
pass
```

---

## Task 2: Client Model Cache Table and DAO

**Files:**

- Create: `client/lib/data/database/tables/model_cache.drift`
- Modify: `client/lib/data/database/app_database.dart`
- Create: `client/lib/data/database/dao/model_cache_dao.dart`
- Create: `client/lib/models/gateway_model.dart`
- Test: `client/test/data/database/model_cache_dao_test.dart`

- [x] **Step 1: Write the failing DAO test**

Create `client/test/data/database/model_cache_dao_test.dart`:

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ModelCacheDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ModelCacheDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('upserts and reads models by user and gateway', () async {
    await dao.upsertModels(
      userId: 'user-a',
      gatewayId: 'hermes',
      models: const [
        CachedGatewayModel(modelId: 'claude-sonnet', displayName: 'claude-sonnet'),
        CachedGatewayModel(modelId: 'gpt-4.1', displayName: 'gpt-4.1'),
      ],
    );

    final models = await dao.getModels('user-a', 'hermes');

    expect(models.map((model) => model.modelId).toList(), [
      'claude-sonnet',
      'gpt-4.1',
    ]);
  });

  test('deleteMissing removes models absent from latest remote response', () async {
    await dao.upsertModels(
      userId: 'user-a',
      gatewayId: 'hermes',
      models: const [
        CachedGatewayModel(modelId: 'old-model', displayName: 'old-model'),
        CachedGatewayModel(modelId: 'kept-model', displayName: 'kept-model'),
      ],
    );

    await dao.deleteMissing('user-a', 'hermes', {'kept-model'});

    final models = await dao.getModels('user-a', 'hermes');
    expect(models.map((model) => model.modelId).toList(), ['kept-model']);
  });
}
```

- [x] **Step 2: Run the failing DAO test**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/data/database/model_cache_dao_test.dart
```

Expected before implementation:

```text
Error: Can't read 'model_cache_dao.dart'
```

- [x] **Step 3: Add model cache table**

Create `client/lib/data/database/tables/model_cache.drift`:

```sql
CREATE TABLE model_cache (
  user_id       TEXT    NOT NULL,
  gateway_id    TEXT    NOT NULL,
  model_id      TEXT    NOT NULL,
  display_name  TEXT    NOT NULL,
  provider      TEXT,
  updated_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, gateway_id, model_id)
);

watchModels:
  SELECT * FROM model_cache
  WHERE user_id = :userId AND gateway_id = :gatewayId
  ORDER BY display_name COLLATE NOCASE ASC, model_id ASC;

getModels:
  SELECT * FROM model_cache
  WHERE user_id = :userId AND gateway_id = :gatewayId
  ORDER BY display_name COLLATE NOCASE ASC, model_id ASC;
```

Modify `client/lib/data/database/app_database.dart`:

```dart
@DriftDatabase(
  include: {
    'tables/conversations.drift',
    'tables/messages.drift',
    'tables/metadata.drift',
    'tables/gateways.drift',
    'tables/task_cache.drift',
    'tables/skill_cache.drift',
    'tables/skill_localizations.drift',
    'tables/model_cache.drift',
  },
)
```

Change:

```dart
int get schemaVersion => 11;
```

Add to `onUpgrade`:

```dart
if (from < 11) {
  await m.createTable(modelCache);
}
```

- [x] **Step 4: Add model cache model and DAO**

Create `client/lib/models/gateway_model.dart`:

```dart
class GatewayModel {
  const GatewayModel({
    required this.modelId,
    required this.displayName,
    this.provider,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  final String modelId;
  final String displayName;
  final String? provider;
  final int updatedAt;
  final int lastSeenAt;
}

class CachedGatewayModel {
  const CachedGatewayModel({
    required this.modelId,
    required this.displayName,
    this.provider,
  });

  final String modelId;
  final String displayName;
  final String? provider;
}
```

Create `client/lib/data/database/dao/model_cache_dao.dart`:

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/models/gateway_model.dart';
import 'package:drift/drift.dart';

class ModelCacheDao {
  ModelCacheDao(this._db);

  final AppDatabase _db;

  Stream<List<GatewayModel>> watchModels(String userId, String gatewayId) {
    return _db
        .watchModels(userId, gatewayId)
        .watch()
        .map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<GatewayModel>> getModels(String userId, String gatewayId) async {
    final rows = await _db.getModels(userId, gatewayId).get();
    return rows.map(_fromRow).toList();
  }

  Future<void> upsertModels({
    required String userId,
    required String gatewayId,
    required List<CachedGatewayModel> models,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final model in models) {
        await _db.into(_db.modelCache).insertOnConflictUpdate(
              ModelCacheCompanion.insert(
                userId: userId,
                gatewayId: gatewayId,
                modelId: model.modelId,
                displayName: model.displayName,
                provider: Value(model.provider),
                updatedAt: now,
                lastSeenAt: now,
              ),
            );
      }
    });
  }

  Future<void> deleteMissing(
    String userId,
    String gatewayId,
    Set<String> remoteModelIds,
  ) async {
    final existing = await getModels(userId, gatewayId);
    for (final model in existing) {
      if (!remoteModelIds.contains(model.modelId)) {
        await (_db.delete(_db.modelCache)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.gatewayId.equals(gatewayId))
              ..where((row) => row.modelId.equals(model.modelId)))
            .go();
      }
    }
  }

  GatewayModel _fromRow(ModelCacheData row) {
    return GatewayModel(
      modelId: row.modelId,
      displayName: row.displayName,
      provider: row.provider,
      updatedAt: row.updatedAt,
      lastSeenAt: row.lastSeenAt,
    );
  }
}
```

- [x] **Step 5: Generate Drift code and run DAO test**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
dart run build_runner build --delete-conflicting-outputs
flutter test test/data/database/model_cache_dao_test.dart
```

Expected:

```text
All tests passed
```

---

## Task 3: Client Models API and Repository

**Files:**

- Create: `client/lib/services/models_api_service.dart`
- Create: `client/lib/data/repositories/model_cache_repository.dart`
- Modify: `client/lib/providers/database_providers.dart`
- Test: `client/test/providers/model_cache_repository_test.dart`

- [x] **Step 1: Write the failing repository test**

Create `client/test/providers/model_cache_repository_test.dart`:

```dart
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/data/repositories/model_cache_repository.dart';
import 'package:client/services/models_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeModelsApiService extends ModelsApiService {
  FakeModelsApiService(this.next);

  List<String> next;
  int calls = 0;

  @override
  Future<List<String>> listModels({
    required String gatewayId,
    bool refresh = false,
  }) async {
    calls += 1;
    return next;
  }
}

void main() {
  late AppDatabase db;
  late ModelCacheDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ModelCacheDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('syncGateway stores remote models and returns cached rows', () async {
    final api = FakeModelsApiService(['claude-sonnet', 'gpt-4.1']);
    final repository = ModelCacheRepository(
      dao: dao,
      api: api,
      userId: 'user-a',
    );

    final models = await repository.syncGateway('hermes');

    expect(models.map((model) => model.modelId).toList(), [
      'claude-sonnet',
      'gpt-4.1',
    ]);
    expect(api.calls, 1);
  });

  test('syncGateway deletes models missing from remote response', () async {
    final api = FakeModelsApiService(['old-model', 'kept-model']);
    final repository = ModelCacheRepository(
      dao: dao,
      api: api,
      userId: 'user-a',
    );

    await repository.syncGateway('hermes');
    api.next = ['kept-model'];
    final models = await repository.syncGateway('hermes');

    expect(models.map((model) => model.modelId).toList(), ['kept-model']);
  });
}
```

- [x] **Step 2: Run the failing repository test**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/providers/model_cache_repository_test.dart
```

Expected before implementation:

```text
Error: Can't read 'model_cache_repository.dart'
```

- [x] **Step 3: Add Models API service**

Create `client/lib/services/models_api_service.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:client/services/media_resolver.dart';

class ModelsApiService {
  late final Dio _dio;

  ModelsApiService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = MediaResolver.baseUrl;
          options.headers.addAll(MediaResolver.authHeaders);
          handler.next(options);
        },
      ),
    );
  }

  Future<List<String>> listModels({
    required String gatewayId,
    bool refresh = false,
  }) async {
    try {
      final params = <String, Object?>{'gateway_id': gatewayId};
      if (refresh) params['refresh'] = '1';
      final response = await _dio.get('/api/models', queryParameters: params);
      final data = Map<String, dynamic>.from(response.data as Map);
      return (data['models'] as List?)?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('[ModelsAPI] listModels error: $e');
      return [];
    }
  }
}
```

- [x] **Step 4: Add ModelCacheRepository**

Create `client/lib/data/repositories/model_cache_repository.dart`:

```dart
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/models/gateway_model.dart';
import 'package:client/services/models_api_service.dart';

class ModelCacheRepository {
  ModelCacheRepository({
    required ModelCacheDao dao,
    required ModelsApiService api,
    required String userId,
  }) : _dao = dao,
       _api = api,
       _userId = userId;

  final ModelCacheDao _dao;
  final ModelsApiService _api;
  final String _userId;

  Stream<List<GatewayModel>> watchModels(String gatewayId) {
    return _dao.watchModels(_userId, gatewayId);
  }

  Future<List<GatewayModel>> getModels(String gatewayId) {
    return _dao.getModels(_userId, gatewayId);
  }

  Future<List<GatewayModel>> syncGateway(String gatewayId) async {
    final remote = await _api.listModels(gatewayId: gatewayId, refresh: true);
    final cached = remote
        .map((modelId) => CachedGatewayModel(modelId: modelId, displayName: modelId))
        .toList();
    await _dao.upsertModels(userId: _userId, gatewayId: gatewayId, models: cached);
    await _dao.deleteMissing(_userId, gatewayId, remote.toSet());
    return getModels(gatewayId);
  }
}
```

- [x] **Step 5: Add providers**

Modify `client/lib/providers/database_providers.dart`:

```dart
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/data/repositories/model_cache_repository.dart';
import 'package:client/services/models_api_service.dart';
```

Add providers:

```dart
final modelsApiServiceProvider = Provider<ModelsApiService>((ref) {
  return ModelsApiService();
});

final modelCacheDaoProvider = Provider<ModelCacheDao>((ref) {
  return ModelCacheDao(ref.watch(databaseProvider));
});

final modelCacheRepositoryProvider = Provider<ModelCacheRepository>((ref) {
  return ModelCacheRepository(
    dao: ref.watch(modelCacheDaoProvider),
    api: ref.watch(modelsApiServiceProvider),
    userId: ref.watch(currentUserUidProvider),
  );
});
```

- [x] **Step 6: Run repository tests**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/providers/model_cache_repository_test.dart
```

Expected:

```text
All tests passed
```

---

## Task 4: Conversation Settings DB-First Loading

**Files:**

- Modify: `client/lib/screens/conversation_settings_sheet.dart`
- Test: `client/test/conversation_settings_sheet_test.dart`

- [x] **Step 1: Write widget tests for DB-first behavior**

Create or extend `client/test/conversation_settings_sheet_test.dart` to cover these behaviors:

```dart
testWidgets('conversation settings shows cached model before remote sync completes', (tester) async {
  // Seed model_cache with "cached-model".
  // Open ConversationSettingsSheet for gateway "hermes".
  // Verify "cached-model" appears without waiting for remote API completion.
});

testWidgets('conversation settings shows cached enabled skills before remote sync completes', (tester) async {
  // Seed skill_cache with enabled skill "weather".
  // Open ConversationSettingsSheet for gateway "hermes".
  // Verify "weather" appears without waiting for remote API completion.
});

testWidgets('conversation settings keeps selected stale model visible', (tester) async {
  // Seed config with selected model "old-model".
  // Seed model_cache without "old-model".
  // Open ConversationSettingsSheet.
  // Verify "old-model" is visible with stale indicator text.
});

testWidgets('conversation settings keeps selected stale skill visible', (tester) async {
  // Seed config with selected skill "old-skill".
  // Seed skill_cache without "old-skill".
  // Open ConversationSettingsSheet.
  // Verify "old-skill" is visible with stale indicator text.
});
```

Use existing app test helpers if present. If no suitable helper exists, create the smallest ProviderScope with overrides for:

- `databaseProvider`
- `modelCacheRepositoryProvider`
- `skillCacheRepositoryProvider`
- `configApiServiceProvider`

- [x] **Step 2: Run widget tests and verify they fail**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/conversation_settings_sheet_test.dart
```

Expected before implementation:

```text
At least one DB-first assertion fails
```

- [x] **Step 3: Replace model loading in ConversationSettingsSheet**

In `client/lib/screens/conversation_settings_sheet.dart`, use:

```dart
final modelRepository = ref.read(modelCacheRepositoryProvider);
final cachedModels = await modelRepository.getModels(widget.accountId);
if (!mounted) return;
setState(() {
  _availableModels = cachedModels.map((model) => model.modelId).toList();
});
unawaited(_refreshModelsFromRemote());
```

Add:

```dart
Future<void> _refreshModelsFromRemote() async {
  final modelRepository = ref.read(modelCacheRepositoryProvider);
  final models = await modelRepository.syncGateway(widget.accountId);
  if (!mounted) return;
  setState(() {
    _availableModels = _mergeSelectedModel(models.map((model) => model.modelId).toList());
  });
}

List<String> _mergeSelectedModel(List<String> models) {
  final selected = _selectedModel;
  if (selected == null || selected.isEmpty || models.contains(selected)) {
    return models;
  }
  return [selected, ...models];
}
```

Add `dart:async` import for `unawaited`.

- [x] **Step 4: Replace skills loading in ConversationSettingsSheet**

Use `SkillCacheRepository`:

```dart
final skillRepository = ref.read(skillCacheRepositoryProvider);
final cachedSkills = await skillRepository.getSkills(widget.accountId, Localizations.localeOf(context).languageCode);
if (!mounted) return;
setState(() {
  _availableSkills = _mergeSelectedSkills(_toSkillInfoList(cachedSkills));
});
unawaited(_refreshSkillsFromRemote());
```

Add:

```dart
Future<void> _refreshSkillsFromRemote() async {
  final skillRepository = ref.read(skillCacheRepositoryProvider);
  final locale = Localizations.localeOf(context).languageCode;
  final scope = SkillScope(
    id: 'gateway:${widget.accountId}',
    type: 'gateway',
    label: widget.accountId,
    description: 'Gateway',
    readonly: false,
    gatewayId: widget.accountId,
  );
  final skills = await skillRepository.syncGateway(scope, locale);
  if (!mounted) return;
  setState(() {
    _availableSkills = _mergeSelectedSkills(_toSkillInfoList(skills));
  });
}

List<SkillInfo> _toSkillInfoList(List<ManagedSkill> skills) {
  return skills
      .where((skill) => skill.enabled)
      .map((skill) => SkillInfo(
            name: skill.name,
            description: skill.displayDescription,
          ))
      .toList();
}

List<SkillInfo> _mergeSelectedSkills(List<SkillInfo> skills) {
  final byName = {for (final skill in skills) skill.name: skill};
  for (final selected in _selectedSkills) {
    byName.putIfAbsent(
      selected,
      () => SkillInfo(name: selected, description: '已失效'),
    );
  }
  return byName.values.toList();
}
```

- [x] **Step 5: Remove settings-page dependency on `ConfigApiService.getSkills` and `getModels`**

Keep `ConfigApiService.getConvConfig` and `saveConvConfig`.

Do not remove `getModels` or `getSkills` from `ConfigApiService` yet, because deprecated Server endpoints are still compatible for older code and tests.

- [x] **Step 6: Run widget tests**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/conversation_settings_sheet_test.dart
```

Expected:

```text
All tests passed
```

---

## Task 5: Integration Checks and Documentation

**Files:**

- Modify: `docs/plans/gateway-resource-cache-plan.md`
- Modify only if needed: existing user-facing docs that mention `/api/config/models` or `/api/config/skills`

- [x] **Step 1: Run focused tests**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/server
npm run build
node --test test/model-routes.test.js
```

Expected:

```text
pass
```

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter test test/data/database/model_cache_dao_test.dart test/providers/model_cache_repository_test.dart test/conversation_settings_sheet_test.dart
```

Expected:

```text
All tests passed
```

- [x] **Step 2: Run analyzers**

Run:

```bash
cd /Users/samy/MyProject/ai/clawke/client
dart analyze lib/data/database/dao/model_cache_dao.dart lib/data/repositories/model_cache_repository.dart lib/services/models_api_service.dart lib/screens/conversation_settings_sheet.dart test/data/database/model_cache_dao_test.dart test/providers/model_cache_repository_test.dart test/conversation_settings_sheet_test.dart
```

Expected:

```text
No issues found
```

Verified on 2026-04-27: command exited 0. Current output contains existing `withOpacity` / `activeColor` deprecation info in `conversation_settings_sheet.dart`, with no analyzer errors or warnings.

- [ ] **Step 3: Run manual macOS smoke test**

Start services:

```bash
cd /Users/samy/MyProject/ai/clawke/server
npm run dev
```

In another terminal, start the Hermes gateway if needed:

```bash
cd /Users/samy/MyProject/ai/clawke
/Users/samy/.hermes/hermes-agent/venv/bin/python run.py
```

Start Client from source:

```bash
cd /Users/samy/MyProject/ai/clawke/client
flutter run -d macos
```

Manual checks:

- Open a conversation settings page.
- Confirm model list appears from cache on second open before gateway refresh finishes.
- Confirm skills list matches Skill Center enabled skills.
- Stop gateway and reopen settings.
- Confirm cached model and skill lists still appear.
- Restart gateway and refresh.
- Confirm remote changes update the local DB.

- [x] **Step 4: Update plan status after implementation**

As each task is completed, update this file by changing task checkboxes from `[ ]` to `[x]`.

---

## Migration Notes

- `/api/config/models` stays available for compatibility and delegates to the same model list logic as `/api/models`.
- `/api/config/skills` stays available for compatibility and is marked deprecated. New Client code must use `/api/skills` through `SkillCacheRepository`.
- Server memory cache remains process-local and short-lived. It is not the UI cache.
- Client Drift cache is the first-screen cache for conversation settings.

## Success Criteria

- Conversation settings no longer blocks first render on model/skill HTTP calls.
- Skills shown in conversation settings come from the same cached data as Skill Center.
- Models are cached locally per user and gateway.
- Gateway offline does not make model/skill pickers empty when local cache exists.
- Deprecated endpoints remain compatible.
- Focused Server and Flutter tests pass.
