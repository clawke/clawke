import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/services/media_resolver.dart';

class TasksApiService {
  late final Dio _dio;

  TasksApiService() {
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

  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    final response = await _dio.get(
      '/api/tasks',
      queryParameters: _accountQuery(accountId),
    );
    final data = _asMap(response.data);
    final list = data['tasks'] as List? ?? [];
    return list
        .map(
          (item) =>
              ManagedTask.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<ManagedTask> createTask(TaskDraft draft) async {
    final response = await _dio.post('/api/tasks', data: draft.toJson());
    final data = _asMap(response.data);
    return ManagedTask.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  Future<ManagedTask> updateTask(String id, TaskDraft draft) async {
    final response = await _dio.put(
      _taskPath(id),
      queryParameters: _accountQuery(draft.accountId),
      data: draft.toPatchJson(),
    );
    final data = _asMap(response.data);
    return ManagedTask.fromJson(Map<String, dynamic>.from(data['task'] as Map));
  }

  Future<ManagedTask?> setEnabled(
    String id,
    String accountId,
    bool enabled,
  ) async {
    final response = await _dio.put(
      '${_taskPath(id)}/enabled',
      queryParameters: _accountQuery(accountId),
      data: {'enabled': enabled},
    );
    final data = _asMap(response.data);
    final task = data['task'];
    if (task is! Map) return null;
    return ManagedTask.fromJson(Map<String, dynamic>.from(task));
  }

  Future<void> deleteTask(String id, String accountId) async {
    await _dio.delete(_taskPath(id), queryParameters: _accountQuery(accountId));
  }

  Future<TaskRun?> runTask(String id, String accountId) async {
    final response = await _dio.post(
      '${_taskPath(id)}/run',
      queryParameters: _accountQuery(accountId),
    );
    final data = _asMap(response.data);
    final run = data['run'];
    if (run is! Map) return null;
    return TaskRun.fromJson(Map<String, dynamic>.from(run));
  }

  Future<List<TaskRun>> listRuns(String id, String accountId) async {
    final response = await _dio.get(
      '${_taskPath(id)}/runs',
      queryParameters: _accountQuery(accountId),
    );
    final data = _asMap(response.data);
    final list = data['runs'] as List? ?? [];
    return list
        .map((item) => TaskRun.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<String> getRunOutput(String id, String runId, String accountId) async {
    final response = await _dio.get(
      '${_taskPath(id)}/runs/${Uri.encodeComponent(runId)}/output',
      queryParameters: _accountQuery(accountId),
    );
    final data = _asMap(response.data);
    return data['output'] as String? ?? '';
  }

  String _taskPath(String id) => '/api/tasks/${Uri.encodeComponent(id)}';

  Map<String, dynamic>? _accountQuery(String? accountId) {
    if (accountId == null || accountId.isEmpty) return null;
    return {'account_id': accountId};
  }

  Map<String, dynamic> _asMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    debugPrint('[TasksAPI] Unexpected response: $data');
    throw const FormatException('Invalid tasks API response');
  }
}
