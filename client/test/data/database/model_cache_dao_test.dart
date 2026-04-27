import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/model_cache_dao.dart';
import 'package:client/models/gateway_model.dart';
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

  test('upsertModels stores and reads models by user and gateway', () async {
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'hermes',
      models: [
        _model('sonnet', 'Sonnet', provider: 'anthropic'),
        _model('opus', 'opus', provider: 'anthropic'),
      ],
    );
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'openclaw',
      models: [_model('other-gateway', 'Other Gateway')],
    );
    await dao.upsertModels(
      userId: 'u2',
      gatewayId: 'hermes',
      models: [_model('other-user', 'Other User')],
    );

    final rows = await dao.getModels('u1', 'hermes');

    expect(rows.map((row) => row.modelId), ['opus', 'sonnet']);
    expect(rows.first.displayName, 'opus');
    expect(rows.last.provider, 'anthropic');
    expect(await dao.getModels('u1', 'openclaw'), hasLength(1));
    expect(await dao.getModels('u2', 'hermes'), hasLength(1));
  });

  test('upsertModels updates existing model metadata', () async {
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'hermes',
      models: [_model('sonnet', 'Sonnet', provider: 'anthropic')],
    );

    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'hermes',
      models: [
        _model(
          'sonnet',
          'Claude Sonnet',
          provider: null,
          updatedAt: 200,
          lastSeenAt: 300,
        ),
      ],
    );

    final row = (await dao.getModels('u1', 'hermes')).single;

    expect(row.displayName, 'Claude Sonnet');
    expect(row.provider, isNull);
    expect(row.updatedAt, 200);
    expect(row.lastSeenAt, 300);
  });

  test('deleteMissing removes models missing from remote set', () async {
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'hermes',
      models: [
        _model('keep', 'Keep'),
        _model('delete-me', 'Delete Me'),
      ],
    );

    await dao.deleteMissing('u1', 'hermes', {'keep'});

    final rows = await dao.getModels('u1', 'hermes');

    expect(rows.map((row) => row.modelId), ['keep']);
  });

  test('deleteMissing preserves other users and gateways', () async {
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'hermes',
      models: [_model('delete-me', 'Delete Me')],
    );
    await dao.upsertModels(
      userId: 'u1',
      gatewayId: 'openclaw',
      models: [_model('other-gateway', 'Other Gateway')],
    );
    await dao.upsertModels(
      userId: 'u2',
      gatewayId: 'hermes',
      models: [_model('other-user', 'Other User')],
    );

    await dao.deleteMissing('u1', 'hermes', <String>{});

    expect(await dao.getModels('u1', 'hermes'), isEmpty);
    expect(await dao.getModels('u1', 'openclaw'), hasLength(1));
    expect(await dao.getModels('u2', 'hermes'), hasLength(1));
  });
}

CachedGatewayModel _model(
  String modelId,
  String displayName, {
  String? provider,
  int updatedAt = 100,
  int lastSeenAt = 100,
}) {
  return CachedGatewayModel(
    modelId: modelId,
    displayName: displayName,
    provider: provider,
    updatedAt: updatedAt,
    lastSeenAt: lastSeenAt,
  );
}
