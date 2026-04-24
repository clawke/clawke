import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/services/media_resolver.dart';

class SkillsApiService {
  late final Dio _dio;

  SkillsApiService() {
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

  Future<List<SkillScope>> listScopes() async {
    final response = await _dio.get('/api/skills/scopes');
    final data = _asMap(response.data);
    final list = data['scopes'] as List? ?? [];
    return list
        .map(
          (item) => SkillScope.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async {
    final response = await _dio.get(
      '/api/skills',
      queryParameters: _scopeQuery(scope),
    );
    final data = _asMap(response.data);
    final list = data['skills'] as List? ?? [];
    return list
        .map(
          (item) =>
              ManagedSkill.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ManagedSkill> getSkill(String id, {SkillScope? scope}) async {
    final response = await _dio.get(
      _skillPath(id),
      queryParameters: _scopeQuery(scope),
    );
    final data = _asMap(response.data);
    return ManagedSkill.fromJson(
      Map<String, dynamic>.from(data['skill'] as Map),
    );
  }

  Future<ManagedSkill> createSkill(SkillDraft draft) async {
    final response = await _dio.post('/api/skills', data: draft.toJson());
    final data = _asMap(response.data);
    return ManagedSkill.fromJson(
      Map<String, dynamic>.from(data['skill'] as Map),
    );
  }

  Future<ManagedSkill> updateSkill(
    String id,
    SkillDraft draft, {
    SkillScope? scope,
  }) async {
    final response = await _dio.put(
      _skillPath(id),
      queryParameters: _scopeQuery(scope),
      data: draft.toJson(),
    );
    final data = _asMap(response.data);
    return ManagedSkill.fromJson(
      Map<String, dynamic>.from(data['skill'] as Map),
    );
  }

  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) async {
    await _dio.put(
      _enabledPath(id),
      queryParameters: _scopeQuery(scope),
      data: {'enabled': enabled},
    );
  }

  Future<void> deleteSkill(String id, {SkillScope? scope}) async {
    await _dio.delete(_skillPath(id), queryParameters: _scopeQuery(scope));
  }

  String _skillPath(String id) {
    final parts = id.split('/');
    if (parts.length != 2) {
      throw ArgumentError('Invalid skill id: $id');
    }
    return '/api/skills/${Uri.encodeComponent(parts[0])}/${Uri.encodeComponent(parts[1])}';
  }

  String _enabledPath(String id) => '${_skillPath(id)}/enabled';

  Map<String, dynamic>? _scopeQuery(SkillScope? scope) {
    if (scope == null) return null;
    final scopeType = scope.isGateway
        ? 'gateway'
        : scope.isAllGateways
        ? 'all'
        : 'library';
    return {
      'scope': scopeType,
      if (scope.gatewayId != null && scope.gatewayId!.isNotEmpty)
        'gateway_id': scope.gatewayId,
    };
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[SkillsAPI] Unexpected response: $data');
    throw const FormatException('Invalid skills API response');
  }
}
