import 'dart:convert';

import 'package:client/models/skillhub_item.dart';
import 'package:client/services/media_resolver.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SkillHubApiException implements Exception {
  final String message;
  final String actionError;
  final Object? details;

  const SkillHubApiException(
    this.message, {
    this.actionError = '',
    this.details,
  });

  List<SkillHubFallbackGateway> get fallbackGateways {
    if (details is! Map) return const [];
    final gateways = (details as Map)['gateways'];
    if (gateways is! List) return const [];
    return gateways
        .whereType<Map>()
        .map((item) => SkillHubFallbackGateway.fromJson(item))
        .where((item) => item.gatewayId.isNotEmpty)
        .toList();
  }

  @override
  String toString() => message;
}

class SkillHubFallbackGateway {
  final String gatewayId;
  final String label;
  final String gatewayType;

  const SkillHubFallbackGateway({
    required this.gatewayId,
    required this.label,
    required this.gatewayType,
  });

  factory SkillHubFallbackGateway.fromJson(Map<dynamic, dynamic> json) {
    final gatewayId = json['gatewayId']?.toString() ?? '';
    return SkillHubFallbackGateway(
      gatewayId: gatewayId,
      label: json['label']?.toString() ?? gatewayId,
      gatewayType: json['gatewayType']?.toString() ?? '',
    );
  }
}

class SkillHubApiService {
  late final Dio _localDio;
  late final Dio _cloudDio;
  SkillHubConfig? _config;

  SkillHubApiService({Dio? localDio, Dio? cloudDio}) {
    _localDio =
        localDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
    _cloudDio =
        cloudDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
          ),
        );
    _localDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.baseUrl = MediaResolver.baseUrl;
          options.headers.addAll(MediaResolver.authHeaders);
          handler.next(options);
        },
      ),
    );
    _cloudDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll(MediaResolver.authHeaders);
          handler.next(options);
        },
      ),
    );
  }

  Future<SkillHubConfig> loadConfig({bool force = false}) async {
    if (!force && _config != null) return _config!;
    final response = await _localDio.get('/api/skillhub/config');
    final config = SkillHubConfig.fromJson(_asMap(response.data));
    _config = config;
    return config;
  }

  Future<SkillHubListResult> listSkills({
    String? query,
    String? category,
    String? tag,
    bool? featured,
    String? gatewayType,
    int? limit,
    String? cursor,
  }) async {
    final config = await loadConfig();
    final value = await _jsonResult(
      () => _cloudDio.get(
        _resolveUrl(config.apiBaseUrl, config.skillsPath),
        queryParameters: _listQuery(
          query: query,
          category: category,
          tag: tag,
          featured: featured,
          gatewayType: gatewayType,
          limit: limit,
          cursor: cursor,
        ),
      ),
    );
    return SkillHubListResult.fromJson(value);
  }

  Future<SkillHubItem> getSkill(String id, {String? gatewayType}) async {
    final config = await loadConfig();
    final value = await _jsonResult(
      () => _cloudDio.get(
        _resolveUrl(config.apiBaseUrl, config.skillPath),
        queryParameters: {
          'id': id,
          if (gatewayType != null && gatewayType.isNotEmpty)
            'gatewayType': gatewayType,
        },
      ),
    );
    return SkillHubItem.fromJson(value);
  }

  Future<SkillHubInstallResult> installSkill(
    SkillHubItem item, {
    String? gatewayId,
    String? gatewayType,
    String? installMode,
  }) async {
    final value = await _jsonResult(
      () => _localDio.post(
        '/api/skillhub/install',
        data: {
          'slug': item.slug,
          'source': item.source.isEmpty ? 'clawhub' : item.source,
          'installMode': installMode ?? 'auto',
          if (gatewayId != null && gatewayId.isNotEmpty)
            'gateway_id': gatewayId,
          if (gatewayType != null && gatewayType.isNotEmpty)
            'gatewayType': gatewayType,
        },
      ),
    );
    return SkillHubInstallResult.fromJson(value);
  }

  Map<String, dynamic>? _listQuery({
    String? query,
    String? category,
    String? tag,
    bool? featured,
    String? gatewayType,
    int? limit,
    String? cursor,
  }) {
    final result = <String, dynamic>{};
    if (query != null && query.isNotEmpty) result['query'] = query;
    if (category != null && category.isNotEmpty) result['category'] = category;
    if (tag != null && tag.isNotEmpty) result['tag'] = tag;
    if (featured != null) result['featured'] = featured;
    if (gatewayType != null && gatewayType.isNotEmpty) {
      result['gatewayType'] = gatewayType;
    }
    if (limit != null) result['limit'] = limit;
    if (cursor != null && cursor.isNotEmpty) result['cursor'] = cursor;
    result['sort'] = 'downloads';
    return result.isEmpty ? null : result;
  }

  Map<String, dynamic> _valueMap(Object? data) {
    final json = _asMap(data);
    if (json['success'] == false) {
      throw _exceptionFromJson(json);
    }
    final value = json['value'];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const SkillHubApiException('Invalid SkillHub response');
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[SkillHubAPI] Unexpected response: $data');
    throw const SkillHubApiException('Invalid SkillHub response');
  }

  String _resolveUrl(String apiBaseUrl, String path) {
    return Uri.parse(apiBaseUrl).resolve(path).toString();
  }

  Future<Map<String, dynamic>> _jsonResult(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      return _valueMap(response.data);
    } on DioException catch (error) {
      throw _exceptionFromDio(error);
    }
  }

  SkillHubApiException _exceptionFromDio(DioException error) {
    final response = error.response;
    final data = response?.data;
    final json = _mapFromResponseData(data);
    if (json != null) return _exceptionFromJson(json);

    final statusCode = response?.statusCode;
    final message = statusCode == null
        ? (error.message ?? 'SkillHub request failed')
        : 'SkillHub request failed (HTTP $statusCode)';
    return SkillHubApiException(
      message,
      actionError: statusCode == null ? 'network_error' : 'http_$statusCode',
    );
  }

  SkillHubApiException _exceptionFromJson(Map<String, dynamic> json) {
    final actionError = json['actionError'] as String? ?? '';
    final message = json['message'] as String? ?? json['error'] as String?;
    return SkillHubApiException(
      message ??
          (actionError.isEmpty ? 'SkillHub request failed' : actionError),
      actionError: actionError,
      details: json['details'],
    );
  }

  Map<String, dynamic>? _mapFromResponseData(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
