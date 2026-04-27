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

  Stream<List<CachedGatewayModel>> watchModels(String gatewayId) {
    return _dao.watchModels(_userId, gatewayId);
  }

  Future<List<CachedGatewayModel>> getModels(String gatewayId) {
    return _dao.getModels(_userId, gatewayId);
  }

  Future<List<CachedGatewayModel>> syncGateway(String gatewayId) async {
    final models = await _api.listModels(gatewayId, refresh: true);
    if (models.isEmpty) {
      return getModels(gatewayId);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final cachedModels = models
        .map(
          (model) => CachedGatewayModel.fromGatewayModel(
            model,
            updatedAt: now,
            lastSeenAt: now,
          ),
        )
        .toList();
    if (cachedModels.isNotEmpty) {
      await _dao.upsertModels(
        userId: _userId,
        gatewayId: gatewayId,
        models: cachedModels,
      );
    }
    await _dao.deleteMissing(_userId, gatewayId, {
      for (final model in cachedModels) model.modelId,
    });
    return getModels(gatewayId);
  }
}
