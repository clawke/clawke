import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:client/services/media_resolver.dart';

/// 会话配置 REST API 客户端
///
/// 通过 CS HTTP Server 读写会话配置（模型、skill、系统提示词等）。
class ConfigApiService {
  late final Dio _dio;

  ConfigApiService() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    // 动态注入 baseUrl 和 token（避免构造时 MediaResolver 还未初始化）
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        options.baseUrl = MediaResolver.baseUrl;
        final headers = MediaResolver.authHeaders;
        options.headers.addAll(headers);
        handler.next(options);
      },
    ));
  }

  /// 查询指定 Gateway 的可用模型列表
  Future<List<String>> getModels({required String accountId, bool refresh = false}) async {
    try {
      final params = <String, String>{'account_id': accountId};
      if (refresh) params['refresh'] = '1';
      final response = await _dio.get(
        '/api/config/models',
        queryParameters: params,
      );
      final data = response.data as Map<String, dynamic>;
      return (data['models'] as List?)?.cast<String>() ?? [];
    } catch (e) {
      debugPrint('[ConfigAPI] getModels error: $e');
      return [];
    }
  }

  /// 查询指定 Gateway 的可用 Skill 列表
  Future<List<SkillInfo>> getSkills({required String accountId, bool refresh = false}) async {
    try {
      final params = <String, String>{'account_id': accountId};
      if (refresh) params['refresh'] = '1';
      final response = await _dio.get(
        '/api/config/skills',
        queryParameters: params,
      );
      final data = response.data as Map<String, dynamic>;
      final list = data['skills'] as List? ?? [];
      return list
          .map((s) => SkillInfo(
                name: s['name'] as String,
                description: s['description'] as String? ?? '',
              ))
          .toList();
    } catch (e) {
      debugPrint('[ConfigAPI] getSkills error: $e');
      return [];
    }
  }

  /// 获取会话配置
  Future<ConvConfig> getConvConfig(String convId) async {
    try {
      final response = await _dio.get('/api/conv/$convId/config');
      final data = response.data as Map<String, dynamic>;
      return ConvConfig.fromJson(data);
    } catch (e) {
      debugPrint('[ConfigAPI] getConvConfig error: $e');
      return ConvConfig(convId: convId);
    }
  }

  /// 保存会话配置
  Future<bool> saveConvConfig(String convId, ConvConfig config) async {
    try {
      await _dio.put(
        '/api/conv/$convId/config',
        data: config.toJson(),
      );
      debugPrint('[ConfigAPI] Saved config for conv=$convId');
      return true;
    } catch (e) {
      debugPrint('[ConfigAPI] saveConvConfig error: $e');
      return false;
    }
  }

  // ─── 会话 CRUD API ───

  /// 获取 Server 上所有会话列表
  Future<List<ServerConv>> getConversations() async {
    try {
      final response = await _dio.get('/api/conversations');
      final list = response.data as List;
      return list.map((e) => ServerConv.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[ConfigAPI] getConversations error: $e');
      return [];
    }
  }

  /// 在 Server 上创建会话
  Future<ServerConv?> createConversation({String? id, String? name, String type = 'dm', String? accountId}) async {
    try {
      final response = await _dio.post('/api/conversations', data: {
        if (id != null) 'id': id,
        if (name != null) 'name': name,
        'type': type,
        if (accountId != null) 'account_id': accountId,
      });
      return ServerConv.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ConfigAPI] createConversation error: $e');
      return null;
    }
  }

  /// 更新 Server 上的会话（name, pin, mute）
  Future<bool> updateConversation(String convId, {String? name, bool? isPinned, bool? isMuted}) async {
    try {
      await _dio.put('/api/conversations/$convId', data: {
        if (name != null) 'name': name,
        if (isPinned != null) 'is_pinned': isPinned,
        if (isMuted != null) 'is_muted': isMuted,
      });
      return true;
    } catch (e) {
      debugPrint('[ConfigAPI] updateConversation error: $e');
      return false;
    }
  }

  /// 在 Server 上删除会话
  Future<bool> deleteConversation(String convId) async {
    try {
      await _dio.delete('/api/conversations/$convId');
      return true;
    } catch (e) {
      debugPrint('[ConfigAPI] deleteConversation error: $e');
      return false;
    }
  }
}

/// Skill 信息
class SkillInfo {
  final String name;
  final String description;

  const SkillInfo({required this.name, required this.description});
}

/// 会话配置
class ConvConfig {
  final String convId;
  final String? accountId;
  final String? modelId;
  final List<String>? skills;
  final String? skillMode; // 'priority' | 'exclusive'
  final String? systemPrompt;
  final String? workDir;

  const ConvConfig({
    required this.convId,
    this.accountId,
    this.modelId,
    this.skills,
    this.skillMode,
    this.systemPrompt,
    this.workDir,
  });

  factory ConvConfig.fromJson(Map<String, dynamic> json) {
    List<String>? skills;
    final rawSkills = json['skills'];
    if (rawSkills is String && rawSkills.isNotEmpty) {
      try {
        skills = (jsonDecode(rawSkills) as List).cast<String>();
      } catch (_) {}
    } else if (rawSkills is List) {
      skills = rawSkills.cast<String>();
    }

    return ConvConfig(
      convId: json['conv_id'] as String? ?? '',
      accountId: json['account_id'] as String?,
      modelId: json['model_id'] as String?,
      skills: skills,
      skillMode: json['skill_mode'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      workDir: json['work_dir'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'account_id': accountId,
        'model_id': modelId,
        'skills': skills != null ? jsonEncode(skills) : null,
        'skill_mode': skillMode,
        'system_prompt': systemPrompt,
        'work_dir': workDir,
      };

  ConvConfig copyWith({
    String? accountId,
    String? modelId,
    List<String>? skills,
    String? skillMode,
    String? systemPrompt,
    String? workDir,
    bool clearModelId = false,
    bool clearSkills = false,
    bool clearSystemPrompt = false,
    bool clearWorkDir = false,
  }) {
    return ConvConfig(
      convId: convId,
      accountId: accountId ?? this.accountId,
      modelId: clearModelId ? null : (modelId ?? this.modelId),
      skills: clearSkills ? null : (skills ?? this.skills),
      skillMode: skillMode ?? this.skillMode,
      systemPrompt:
          clearSystemPrompt ? null : (systemPrompt ?? this.systemPrompt),
      workDir: clearWorkDir ? null : (workDir ?? this.workDir),
    );
  }
}

/// Server 端返回的会话数据
class ServerConv {
  final String id;
  final String type;
  final String? name;
  final String? accountId;
  final bool isPinned;
  final bool isMuted;
  final int createdAt;
  final int updatedAt;

  const ServerConv({
    required this.id,
    required this.type,
    this.name,
    this.accountId,
    this.isPinned = false,
    this.isMuted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServerConv.fromJson(Map<String, dynamic> json) {
    return ServerConv(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'dm',
      name: json['name'] as String?,
      accountId: json['account_id'] as String?,
      isPinned: json['is_pinned'] == true || json['is_pinned'] == 1,
      isMuted: json['is_muted'] == true || json['is_muted'] == 1,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
    );
  }
}
