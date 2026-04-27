import 'package:client/models/gateway_model.dart';
import 'package:client/services/media_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ModelsApiService {
  late final Dio _dio;

  ModelsApiService({Dio? dio}) {
    _dio =
        dio ??
        Dio(
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

  Future<List<GatewayModel>> listModels(
    String gatewayId, {
    bool refresh = false,
  }) async {
    final response = await _dio.get(
      '/api/models',
      queryParameters: {'gateway_id': gatewayId, if (refresh) 'refresh': '1'},
    );
    final data = _asMap(response.data);
    final list = data['models'] as List? ?? const [];
    return list
        .map(_toModel)
        .where((model) => model.modelId.isNotEmpty)
        .toList();
  }

  GatewayModel _toModel(Object? item) {
    if (item is String) {
      return GatewayModel(modelId: item, displayName: item);
    }
    if (item is Map) {
      return GatewayModel.fromJson(Map<String, dynamic>.from(item));
    }
    debugPrint('[ModelsAPI] Unexpected model item: $item');
    throw const FormatException('Invalid models API item');
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[ModelsAPI] Unexpected response: $data');
    throw const FormatException('Invalid models API response');
  }
}
