import 'package:client/models/usage_dashboard.dart';
import 'package:client/services/media_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DashboardApiService {
  late final Dio _dio;

  DashboardApiService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
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

  Future<UsageDashboard> getUsage({String? gatewayId}) async {
    final response = await _dio.get(
      '/api/dashboard/usage',
      queryParameters: _gatewayQuery(gatewayId),
    );
    return UsageDashboard.fromJson(_asMap(response.data));
  }

  Map<String, dynamic>? _gatewayQuery(String? gatewayId) {
    if (gatewayId == null || gatewayId.isEmpty) return null;
    return {'gateway_id': gatewayId};
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[DashboardAPI] Unexpected response: $data');
    throw const FormatException('Invalid dashboard API response');
  }
}
