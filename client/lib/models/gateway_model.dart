class GatewayModel {
  final String modelId;
  final String displayName;
  final String? provider;

  const GatewayModel({
    required this.modelId,
    required this.displayName,
    this.provider,
  });

  factory GatewayModel.fromJson(Map<String, dynamic> json) {
    final modelId = json['model_id'] as String? ?? json['id'] as String? ?? '';
    return GatewayModel(
      modelId: modelId,
      displayName:
          json['display_name'] as String? ?? json['name'] as String? ?? modelId,
      provider: json['provider'] as String?,
    );
  }
}

class CachedGatewayModel extends GatewayModel {
  final int updatedAt;
  final int lastSeenAt;

  const CachedGatewayModel({
    required super.modelId,
    required super.displayName,
    super.provider,
    required this.updatedAt,
    required this.lastSeenAt,
  });

  factory CachedGatewayModel.fromGatewayModel(
    GatewayModel model, {
    required int updatedAt,
    required int lastSeenAt,
  }) {
    return CachedGatewayModel(
      modelId: model.modelId,
      displayName: model.displayName,
      provider: model.provider,
      updatedAt: updatedAt,
      lastSeenAt: lastSeenAt,
    );
  }
}
