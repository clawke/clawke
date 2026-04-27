import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/data/repositories/model_cache_repository.dart';
import 'package:client/models/gateway_model.dart';
import 'package:client/services/models_api_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeModelsApi extends ModelsApiService {
  List<GatewayModel> models = const [];
  String? lastGatewayId;
  bool? lastRefresh;

  @override
  Future<List<GatewayModel>> listModels(
    String gatewayId, {
    bool refresh = false,
  }) async {
    lastGatewayId = gatewayId;
    lastRefresh = refresh;
    return models;
  }
}

void main() {
  late AppDatabase db;
  late ModelCacheDao dao;
  late _FakeModelsApi api;
  late ModelCacheRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ModelCacheDao(db);
    api = _FakeModelsApi();
    repo = ModelCacheRepository(dao: dao, api: api, userId: 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  test('syncGateway stores remote models and returns cached rows', () async {
    api.models = const [
      GatewayModel(
        modelId: 'claude-3-5-sonnet',
        displayName: 'Claude 3.5 Sonnet',
        provider: 'anthropic',
      ),
      GatewayModel(modelId: 'local-model', displayName: 'local-model'),
    ];

    final synced = await repo.syncGateway('hermes');
    final cached = await repo.getModels('hermes');

    expect(api.lastGatewayId, 'hermes');
    expect(api.lastRefresh, isTrue);
    expect(synced.map((model) => model.modelId), [
      'claude-3-5-sonnet',
      'local-model',
    ]);
    expect(cached.map((model) => model.displayName), [
      'Claude 3.5 Sonnet',
      'local-model',
    ]);
    expect(cached.first.provider, 'anthropic');
  });

  test('syncGateway deletes models missing from remote result', () async {
    api.models = const [
      GatewayModel(modelId: 'keep', displayName: 'Keep'),
      GatewayModel(modelId: 'remove', displayName: 'Remove'),
    ];
    await repo.syncGateway('hermes');

    api.models = const [GatewayModel(modelId: 'keep', displayName: 'Keep')];
    final synced = await repo.syncGateway('hermes');

    expect(synced.map((model) => model.modelId), ['keep']);
    expect((await repo.getModels('hermes')).map((model) => model.modelId), [
      'keep',
    ]);
  });

  test('syncGateway keeps cache when remote returns empty models', () async {
    api.models = const [
      GatewayModel(modelId: 'cached-model', displayName: 'Cached Model'),
    ];
    await repo.syncGateway('hermes');

    api.models = const [];
    final synced = await repo.syncGateway('hermes');

    expect(synced.map((model) => model.modelId), ['cached-model']);
    expect((await repo.getModels('hermes')).map((model) => model.modelId), [
      'cached-model',
    ]);
  });

  test('syncGateway calls API with refresh true', () async {
    api.models = const [];

    await repo.syncGateway('hermes');

    expect(api.lastRefresh, isTrue);
  });
}
