import 'package:client/data/database/app_database.dart';
import 'package:client/models/gateway_model.dart';
import 'package:drift/drift.dart';

class ModelCacheDao {
  final AppDatabase _db;
  ModelCacheDao(this._db);

  Stream<List<CachedGatewayModel>> watchModels(String userId, String gatewayId) {
    return _db
        .watchModels(userId, gatewayId)
        .watch()
        .map((rows) => rows.map(_fromRow).toList());
  }

  Future<List<CachedGatewayModel>> getModels(
    String userId,
    String gatewayId,
  ) async {
    final rows = await _db.getModels(userId, gatewayId).get();
    return rows.map(_fromRow).toList();
  }

  Future<void> upsertModels({
    required String userId,
    required String gatewayId,
    required List<CachedGatewayModel> models,
  }) {
    return _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.modelCache,
        models.map(
          (model) => ModelCacheCompanion.insert(
            userId: userId,
            gatewayId: gatewayId,
            modelId: model.modelId,
            displayName: model.displayName,
            provider: Value(model.provider),
            updatedAt: model.updatedAt,
            lastSeenAt: model.lastSeenAt,
          ),
        ),
      );
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
}

CachedGatewayModel _fromRow(ModelCacheData row) {
  return CachedGatewayModel(
    modelId: row.modelId,
    displayName: row.displayName,
    provider: row.provider,
    updatedAt: row.updatedAt,
    lastSeenAt: row.lastSeenAt,
  );
}
