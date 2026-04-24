import 'dart:async';

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/models/message_model.dart';
import 'package:client/core/cup_parser.dart';
import 'package:client/providers/approval_provider.dart';
import 'package:client/core/notification_service.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/data/repositories/message_repository.dart' show deviceId;
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/chat_limit_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/nav_page_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/upgrade/upgrade_handler.dart';
import 'package:client/core/file_logger.dart';

final _fl = FileLogger.instance;

// 当前正在流式输出的消息（高频变化，单独隔离）
final streamingMessageProvider = StateProvider<TextMessage?>((ref) => null);

// 当前正在流式输出的 thinking 内容
final streamingThinkingProvider = StateProvider<ThinkingMessage?>(
  (ref) => null,
);

// 等待 AI 回复的中间状态（发送后、首个 delta 到达前）
// 存储正在等待回复的 conversationId（null = 不在等待）
final waitingForReplyProvider = StateProvider<String?>((ref) => null);

// 当前正在执行的工具（null = 没有工具调用中）
// 包含 convId 以确保只在对应会话中显示
final activeToolProvider = StateProvider<({String name, String convId})?>((ref) => null);

// 全局 SDUI 弹窗组件（如 Dashboard, CronList 等），通过 ref.listen 在 UI 顶层展示
final globalSduiProvider = StateProvider<SduiMessage?>((ref) => null);

// 认证失败标记（WS 连接被 401 拒绝 → token 过期/无效）
final authFailedProvider = StateProvider<bool>((ref) => false);

/// 最近一次 AI 回复的 Token 用量（按会话隔离）
final lastUsageReportProvider = StateProvider.family<UsageReport?, String>(
  (ref, accountId) => null,
);

/// Token 用量数据（来自 OpenClaw llm_output Plugin Hook）
class UsageReport {
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;
  final int total;
  final String model;
  final String provider;

  const UsageReport({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.total = 0,
    this.model = '',
    this.provider = '',
  });

  /// 格式化显示：⚡ 1,234 in · 856 out · 12.4K cache │ model
  String get formattedLabel {
    final parts = <String>[];
    if (input > 0) parts.add('${_formatCount(input)} in');
    if (output > 0) parts.add('${_formatCount(output)} out');
    if (cacheRead > 0) parts.add('${_formatCount(cacheRead)} cache');
    final tokenPart = parts.join(' · ');
    final modelPart = model.isNotEmpty ? ' │ $model' : '';
    return '⚡ $tokenPart$modelPart';
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

// WebSocket 消息处理器 — 负责监听 WS 并写入 DB
final wsMessageHandlerProvider = Provider<WsMessageHandler>((ref) {
  final handler = WsMessageHandler(ref);
  ref.onDispose(handler.dispose);
  return handler;
});

class WsMessageHandler with WidgetsBindingObserver {
  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _sub;
  late final WsService _ws;

  /// 待确认的请求：requestId → clientMsgId
  final Map<String, String> _pendingRequests = {};

  /// 待确认请求的会话路由：requestId → conversationId
  final Map<String, String> _pendingConversationIds = {};

  /// 当前流式消息关联的 accountId
  String? _streamingAccountId;

  /// 当前流式消息关联的 conversationId
  String? _streamingConversationId;

  // ── 流式 debounce 缓冲 ──────────────────────────
  // 累积 delta 到缓冲区，定时刷新到 provider，减少 GptMarkdown 重建次数
  Timer? _textFlushTimer;
  String _textBuffer = '';
  String? _textBufferMsgId;

  Timer? _thinkingFlushTimer;
  String _thinkingBuffer = '';
  String? _thinkingBufferMsgId;

  /// 根据已有文本长度自适应节流间隔（长文本减少重建频率）
  int _throttleMs(int currentLength) => currentLength > 3000 ? 100 : 50;

  /// Debounce 开关（关闭后每个 delta 立即刷新 UI，开启后合并刷新）
  static const _enableDebounce = false;

  WsMessageHandler(this._ref) {
    _ws = _ref.read(wsServiceProvider);
    _sub = _ws.messageStream.listen(_handleIncoming);
    _fl.log('[INIT] WsMessageHandler started');

    // 设置重连回调
    _ws.onConnected = _onConnected;

    // 设置认证失败回调（token 被拒 → 弹窗提示重新登录）
    _ws.onAuthFailed = () {
      debugPrint('[WsMessageHandler] 🔒 Auth failed, prompting re-login');
      _ref.read(authFailedProvider.notifier).state = true;
    };

    // 监听 App 生命周期（息屏/后台 → 恢复时主动 sync）
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[WsMessageHandler] App resumed, checking WS & syncing');
      if (_ws.state == WsState.connected) {
        // WS 还连着（短暂息屏），直接发 sync 拉增量
        _sendSync();
        // 同步会话列表
        _ref.read(conversationRepositoryProvider).syncFromServer();
      } else {
        // WS 已断，触发重连（重连成功后 onReconnected 会自动 sync）
        _ws.reconnect();
      }
    }
  }

  /// 注册待确认请求
  void trackRequest(String requestId, String clientMsgId, {String? conversationId}) {
    _pendingRequests[requestId] = clientMsgId;
    if (conversationId != null) {
      _pendingConversationIds[requestId] = conversationId;
    }
    debugPrint(
      '[WsHandler] 📤 trackRequest: reqId=$requestId, clientMsgId=$clientMsgId, convId=$conversationId',
    );
  }

  void _onConnected() {
    debugPrint('[WsMessageHandler] Connected, sending sync request');
    // 重连时清除流式状态，防止跨会话路由错误
    _streamingAccountId = null;
    _streamingConversationId = null;
    // 重连时清空在线后端列表，等 ai_connected 消息重建
    _ref.read(connectedAccountsProvider.notifier).state = [];
    _sendSync();
    // 同步会话列表（Server 权威 → 本地对齐）
    _ref.read(conversationRepositoryProvider).syncFromServer();
  }

  /// DB metadata key for sync seq baseline.
  static const _kLastSyncSeq = 'last_sync_seq';

  Future<void> _sendSync() async {
    final db = _ref.read(databaseProvider);
    final stored = await db.getMetadata(_kLastSyncSeq);
    int lastSeq;

    if (stored != null) {
      lastSeq = int.tryParse(stored) ?? 0;
    } else {
      // 首次迁移：从消息表获取最大 seq 作为初始值
      final msgDao = _ref.read(messageDaoProvider);
      lastSeq = await msgDao.getMaxSeq();
      await db.setMetadata(_kLastSyncSeq, lastSeq.toString());
      debugPrint('[WsMessageHandler] Initialized last_sync_seq from DB messages: $lastSeq');
    }

    final ws = _ref.read(wsServiceProvider);
    ws.sendJson({
      'id': 'sync_${DateTime.now().millisecondsSinceEpoch}',
      'protocol': 'cup_v2',
      'event_type': 'sync',
      'data': {
        'last_seq': lastSeq,
        'app_version': _appVersion,
        'platform': _platform,
        'arch': _arch,
      },
    });
    debugPrint(
      '[WsMessageHandler] Sent sync, last_seq=$lastSeq, version=$_appVersion',
    );
  }

  /// 推进 sync 基线：实时收到的消息（text_done/ctrl ACK/echo）
  /// 也需要更新 DB metadata，否则下次 sync 会重复拉取。
  Future<void> _advanceSyncSeq(int seq) async {
    if (seq <= 0) return;
    final db = _ref.read(databaseProvider);
    final stored = await db.getMetadata(_kLastSyncSeq);
    final current = int.tryParse(stored ?? '0') ?? 0;
    if (seq > current) {
      await db.setMetadata(_kLastSyncSeq, seq.toString());
    }
  }

  void sendCheckUpdate() {
    _ws.sendJson({
      'event_type': 'check_update',
      'data': {
        'app_version': _appVersion,
        'platform': _platform,
        'arch': _arch,
      },
    });
    debugPrint('[WsMessageHandler] Sent check_update');
  }

  void requestDashboard() {
    final locale = _ref.read(localeProvider);
    final lang = locale?.languageCode ?? 'zh';
    _ws.sendJson({
      'event_type': 'request_dashboard',
      'data': {'locale': lang},
    });
    debugPrint('[WsMessageHandler] Sent requestDashboard (locale=$lang)');
  }

  /// 发送审批响应（Client → Server → Gateway）
  void sendApprovalResponse(String choice) {
    final request = _ref.read(activeApprovalProvider);
    if (request == null) {
      debugPrint('[WsMessageHandler] ⚠️ sendApprovalResponse: activeApprovalProvider is NULL, skipping');
      return;
    }

    final conv = _ref.read(selectedConversationProvider);
    final accountId = conv?.accountId ?? 'default';

    debugPrint('[WsMessageHandler] 🔐 sendApprovalResponse: choice=$choice, accountId=$accountId, conv=${request.conversationId}, wsState=${_ws.state}');

    _ws.sendJson({
      'event_type': 'approval_response',
      'context': {
        'account_id': accountId,
        'conversation_id': request.conversationId,
      },
      'data': {
        'conversation_id': request.conversationId,
        'choice': choice,
      },
    });
    debugPrint('[WsMessageHandler] ✅ Sent approval_response: choice=$choice, conv=${request.conversationId}, account=$accountId');

    // 持久化审批结果到 DB（code fence 标签格式）
    final result = (choice == 'deny') ? 'denied' : 'approved';
    final lines = <String>[
      '```approval_result',
      if (request.description.isNotEmpty) 'description: ${request.description}',
      if (request.command.isNotEmpty) 'command: ${request.command}',
      'result: $result',
      '```',
    ];
    _ref.read(messageRepositoryProvider).receiveMessage(
      messageId: 'approval_result_${DateTime.now().millisecondsSinceEpoch}',
      accountId: accountId,
      conversationId: request.conversationId,
      senderId: 'system',
      type: 'text',
      content: lines.join('\n'),
      seq: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 清除卡片
    _ref.read(activeApprovalProvider.notifier).state = null;
  }

  /// 发送澄清响应（Client → Server → Gateway）
  void sendClarifyResponse(String response) {
    final request = _ref.read(activeClarifyProvider);
    if (request == null) return;

    final conv = _ref.read(selectedConversationProvider);
    final accountId = conv?.accountId ?? 'default';

    _ws.sendJson({
      'event_type': 'clarify_response',
      'context': {
        'account_id': accountId,
        'conversation_id': request.conversationId,
      },
      'data': {
        'conversation_id': request.conversationId,
        'response': response,
      },
    });
    debugPrint('[WsMessageHandler] 💬 Sent clarify_response: response="${response.length > 40 ? '${response.substring(0, 40)}...' : response}", conv=${request.conversationId}');

    // 持久化澄清结果到 DB（code fence 标签格式）
    _ref.read(messageRepositoryProvider).receiveMessage(
      messageId: 'clarify_result_${DateTime.now().millisecondsSinceEpoch}',
      accountId: accountId,
      conversationId: request.conversationId,
      senderId: 'system',
      type: 'text',
      content: '```clarify_result\nquestion: ${request.question}\nanswer: $response\n```',
      seq: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    // 清除卡片
    _ref.read(activeClarifyProvider.notifier).state = null;
  }

  void sendAbort() {
    final conv = _ref.read(selectedConversationProvider)!;
    final convId = conv.conversationId;
    final accountId = conv.accountId;

    _ws.sendJson({
      'event_type': 'abort',
      'context': {
        'account_id': accountId,
        'conversation_id': convId,
      },
      'data': {'account_id': convId},
    });
    debugPrint('[WsMessageHandler] Sent abort for conv=$convId, account=$accountId');

    // 立即清除客户端流式状态（不等服务端确认）
    // text_done 到达后 _finalizeStreaming 会 upsert（同 ID 覆盖），不会重复
    _finalizeStreaming({'account_id': convId});
    _ref.read(waitingForReplyProvider.notifier).state = null;
    _ref.read(streamingThinkingProvider.notifier).state = null;
  }

  // 版本信息（后续可从 package_info_plus 获取）
  static const String _appVersion = '0.1.0';
  String get _platform {
    if (defaultTargetPlatform == TargetPlatform.macOS) return 'macos';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'windows';
    if (defaultTargetPlatform == TargetPlatform.linux) return 'linux';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    return 'unknown';
  }

  // TODO: 通过 dart:ffi 或 package_info_plus 获取真实 arch
  static const String _arch = 'arm64';

  void _handleIncoming(Map<String, dynamic> json) {
    final payloadType = json['payload_type'] as String?;
    if (payloadType == 'system_status') {
      final status = json['status'] as String? ?? '';
      final agentName = json['agent_name'] as String? ?? '';
      final message = json['message'] as String? ?? '';
      debugPrint(
        '[WsMessageHandler] 收到: system_status | status=$status, agent=$agentName${message.isNotEmpty ? ', msg=$message' : ''}',
      );

      // 升级通知 — 直接从 raw JSON 处理（SystemMessage model 不含升级字段）
      if (status == 'update_available' || status == 'up_to_date') {
        if (status == 'update_available') {
          UpgradeHandler.handleSystemStatusFromRef(json, _ref);
          debugPrint('[WsMessageHandler] 🚀 Update available');
        }
        return;
      }
    } else {
      debugPrint(
        '[WsMessageHandler] 收到: $payloadType | ${json['message_id'] ?? json['id'] ?? ''}',
      );
    }

    switch (payloadType) {
      case 'ctrl':
        _handleCtrl(json);
        return;
      case 'sync_response':
        _handleSyncResponse(json);
        return;
      case 'message_echo':
        _handleMessageEcho(json);
        return;
      case 'usage_report':
        _handleUsageReport(json);
        return;
      case 'conv_changed':
        debugPrint('[WsMessageHandler] 收到 conv_changed，同步会话列表');
        _ref.read(conversationRepositoryProvider).syncFromServer();
        return;
      case 'typing_start':
        final typingConvId = json['conversation_id'] as String?;
        debugPrint('[WsMessageHandler] ⌨️ typing_start: conv=$typingConvId');
        if (typingConvId != null) {
          _ref.read(waitingForReplyProvider.notifier).state = typingConvId;
        }
        return;
      case 'agent_status':
        final status = json['status'] as String? ?? '';
        final convId = json['conversation_id'] as String?;
        debugPrint('[WsMessageHandler] 🔄 agent_status: status=$status, conv=$convId');
        // queued 状态：消息已入队等待前一个请求完成，保持等待指示
        if (status == 'queued' && convId != null) {
          _ref.read(waitingForReplyProvider.notifier).state = convId;
        }
        return;
      case 'tool_call_start':
        final toolTitle = json['tool_title'] as String? ?? '';
        final toolName = json['tool_name'] as String? ?? 'tool';
        final displayName = toolTitle.isNotEmpty ? toolTitle : toolName;
        // 已有丰富描述且新消息无 title → 不覆盖
        final current = _ref.read(activeToolProvider);
        if (current != null && toolTitle.isEmpty) return;
        final convId = json['conversation_id'] as String? ?? _streamingConversationId ?? '';
        debugPrint('[WsMessageHandler] 🔧 tool_call_start: $displayName (conv=$convId)');
        _ref.read(activeToolProvider.notifier).state = (name: displayName, convId: convId);
        return;
      case 'tool_call_done':
        final doneToolName = json['tool_name'] as String? ?? 'tool';
        final durationMs = json['duration_ms'] as int? ?? 0;
        debugPrint('[WsMessageHandler] ✅ tool_call_done: $doneToolName (${durationMs}ms)');
        // 不清除 activeToolProvider — 保持工具指示器显示，直到 text_delta 到达
        return;
      case 'approval_request':
        _handleApprovalRequest(json);
        return;
      case 'clarify_request':
        _handleClarifyRequest(json);
        return;
    }

    // thinking 处理
    if (CupParser.isThinkingDelta(json)) {
      _appendThinkingDelta(
        json['message_id'] as String? ?? 'unknown',
        json['content'] as String? ?? '',
        json['account_id'] as String?,
        json['conversation_id'] as String?,
      );
      return;
    } else if (CupParser.isThinkingDone(json)) {
      _finalizeThinking();
      return;
    }

    // 原有逻辑：text_delta, text_done, system_status, 其他
    if (CupParser.isTextDelta(json)) {
      _appendTextDelta(
        json['message_id'] as String? ?? 'unknown',
        json['content'] as String? ?? '',
        json['account_id'] as String?,
        json['conversation_id'] as String?,
      );
    } else if (CupParser.isTextDone(json)) {
      _finalizeStreaming(json);
    } else {
      final model = CupParser.parse(json);
      if (model is SystemMessage) {
        _handleSystemStatus(model);
      } else if (model != null) {
        _writeToDb(model, json);
      }
    }
  }

  void _handleCtrl(Map<String, dynamic> json) {
    final requestId = json['id'] as String?;
    final code = json['code'] as int?;
    final params = json['params'] as Map<String, dynamic>?;

    if (requestId == null) return;

    final clientMsgId = _pendingRequests[requestId];
    if (clientMsgId == null) {
      debugPrint(
        '[WsMessageHandler] ctrl received unknown requestId: $requestId',
      );
      return;
    }

    final msgDao = _ref.read(messageDaoProvider);

    if (code == 200) {
      // ACK — sent（Clawke Server 收到）
      final serverMsgId = params?['server_msg_id'] as String?;
      final seq = params?['seq'] as int?;
      msgDao.updateStatus(clientMsgId, 'sent', serverId: serverMsgId, seq: seq);
      if (seq != null) _advanceSyncSeq(seq);
      // 在回复到达前锁定 conversationId → 确保多会话路由正确
      final trackedConvId = _pendingConversationIds[requestId];
      if (trackedConvId != null) {
        _streamingConversationId = trackedConvId;
      }
      debugPrint(
        '[WsMessageHandler] ACK sent: $clientMsgId → $serverMsgId, seq=$seq, convId=$trackedConvId',
      );
    } else if (code == 201) {
      // delivered — OpenClaw Gateway 收到
      msgDao.updateStatus(clientMsgId, 'delivered');
      _pendingConversationIds.remove(requestId);
      _pendingRequests.remove(requestId);
      debugPrint('[WsMessageHandler] ACK delivered: $clientMsgId');
    }
  }

  Future<void> _handleMessageEcho(Map<String, dynamic> json) async {
    final senderDeviceId = json['sender_device_id'] as String? ?? '';
    final messageId = json['message_id'] as String? ?? '';

    debugPrint('[WsMessageHandler] message_echo: msgId=$messageId, senderDevice=$senderDeviceId, localDevice=$deviceId');

    // 跳过自己设备发的 echo（已在本地 DB）
    if (senderDeviceId == deviceId) {
      debugPrint('[WsMessageHandler] message_echo SKIP: same device');
      return;
    }

    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      debugPrint('[WsMessageHandler] message_echo SKIP: data is null');
      return;
    }

    final accountId = json['account_id'] as String? ?? 'default';
    final conversationId = json['conversation_id'] as String? ?? accountId;
    final type = data['type'] as String? ?? 'text';
    // 对于 image/file 类型：序列化 media 元数据为 JSON（发送方存的是本地路径，但接收方需要 URL 信息）
    final String content;
    if (type == 'image' && (data.containsKey('mediaUrl') || data.containsKey('thumbHash'))) {
      content = jsonEncode({
        'mediaUrl': data['mediaUrl'],
        'thumbUrl': data['thumbUrl'],
        'thumbHash': data['thumbHash'],
        'width': data['width'],
        'height': data['height'],
        'fileName': data['fileName'],
      });
    } else if (type == 'file' && data.containsKey('mediaUrl')) {
      content = jsonEncode({
        'mediaUrl': data['mediaUrl'],
        'mediaType': data['mediaType'],
        'name': data['fileName'] ?? data['name'] ?? 'unknown',
        'size': data['fileSize'] ?? data['size'] ?? 0,
      });
    } else {
      content = data['content'] as String? ?? '';
    }
    final finalMsgId = messageId.isNotEmpty ? messageId : 'echo_${DateTime.now().millisecondsSinceEpoch}';
    final createdAt = json['created_at'] as int?;

    // DB 去重
    final msgDao = _ref.read(messageDaoProvider);
    final existing = await msgDao.getMessage(finalMsgId);
    if (existing != null) {
      debugPrint('[WsMessageHandler] message_echo SKIP: already in DB ($finalMsgId)');
      return;
    }

    debugPrint('[WsMessageHandler] message_echo WRITE: $finalMsgId → convId=$conversationId');

    final repo = _ref.read(messageRepositoryProvider);
    await repo.receiveMessage(
      messageId: finalMsgId,
      accountId: accountId,
      conversationId: conversationId,
      senderId: 'local_user',
      type: type,
      content: content,
      seq: 0,
      createdAt: createdAt,
    );

    // 当前选中会话则清零未读
    if (conversationId == _ref.read(selectedConversationIdProvider)) {
      _ref.read(conversationRepositoryProvider).markAsRead(conversationId);
    }
  }

  Future<void> _handleSyncResponse(Map<String, dynamic> json) async {
    final messages = json['messages'] as List<dynamic>? ?? [];
    final currentSeq = json['current_seq'] as int?;
    debugPrint('[WsMessageHandler] sync_response: ${messages.length} messages, current_seq=$currentSeq');

    final repo = _ref.read(messageRepositoryProvider);
    final selectedConvId = _ref.read(selectedConversationIdProvider);
    final touchedConvIds = <String>{};

    for (final m in messages) {
      final map = m as Map<String, dynamic>;
      // 按 message_id 去重：client_msg_id（用户消息）和 message_id（AI 消息）都要查
      final clientMsgId = map['client_msg_id'] as String?;
      final serverMsgId = map['message_id'] as String?;
      final msgId = clientMsgId ?? serverMsgId ?? 'unknown';

      // 两个 ID 都查一遍，任一存在即跳过
      final dao = _ref.read(messageDaoProvider);
      if (clientMsgId != null && await dao.getMessage(clientMsgId) != null) continue;
      if (serverMsgId != null && await dao.getMessage(serverMsgId) != null) continue;

      final accountId = map['account_id'] as String? ?? 'default';
      final conversationId = map['conversation_id'] as String? ?? accountId;
      touchedConvIds.add(conversationId);

      final msgType = map['type'] as String? ?? 'text';
      final String msgContent;
      if (msgType == 'image' && (map.containsKey('mediaUrl') || map.containsKey('thumbHash'))) {
        msgContent = jsonEncode({
          'mediaUrl': map['mediaUrl'],
          'thumbUrl': map['thumbUrl'],
          'thumbHash': map['thumbHash'],
          'width': map['width'],
          'height': map['height'],
          'fileName': map['fileName'],
        });
      } else if (msgType == 'file' && map.containsKey('mediaUrl')) {
        msgContent = jsonEncode({
          'mediaUrl': map['mediaUrl'],
          'mediaType': map['mediaType'],
          'name': map['fileName'] ?? map['name'] ?? 'unknown',
          'size': map['fileSize'] ?? map['size'] ?? 0,
        });
      } else {
        msgContent = map['content'] as String? ?? '';
      }

      await repo.receiveMessage(
        messageId: msgId,
        accountId: accountId,
        conversationId: conversationId,
        senderId: map['sender_id'] as String? ?? 'agent',
        type: msgType,
        content: msgContent,
        serverId: map['message_id'] as String?,
        seq: map['seq'] as int? ?? 0,
        createdAt: map['ts'] as int?,
      );
    }

    // 当前选中的会话在 sync 中被更新了，清零未读
    if (selectedConvId != null && touchedConvIds.contains(selectedConvId)) {
      _ref.read(conversationRepositoryProvider).markAsRead(selectedConvId);
    }

    // 始终用服务端的 current_seq 更新本地 sync 基线
    // 即使 current_seq < 本地值（服务端被重装），也直接覆盖
    if (currentSeq != null && currentSeq >= 0) {
      final db = _ref.read(databaseProvider);
      final stored = await db.getMetadata(_kLastSyncSeq);
      final oldSeq = int.tryParse(stored ?? '0') ?? 0;
      await db.setMetadata(_kLastSyncSeq, currentSeq.toString());
      if (currentSeq < oldSeq) {
        debugPrint(
          '[WsMessageHandler] ⚠️ Server seq reset detected: server=$currentSeq < local=$oldSeq → updated baseline',
        );
      } else {
        debugPrint('[WsMessageHandler] Updated last_sync_seq: $oldSeq → $currentSeq');
      }
    }
  }

  void _handleUsageReport(Map<String, dynamic> json) {
    final convId = json['conversation_id'] as String? ?? json['account_id'] as String? ?? 'default';
    final msgId = json['message_id'] as String?;
    final usage = json['usage'] as Map<String, dynamic>?;
    if (usage == null) return;

    final inputTokens = (usage['input'] as num?)?.toInt() ?? 0;
    final outputTokens = (usage['output'] as num?)?.toInt() ?? 0;
    final model = json['model'] as String? ?? '';

    _ref.read(lastUsageReportProvider(convId).notifier).state = UsageReport(
      input: inputTokens,
      output: outputTokens,
      cacheRead: (usage['cacheRead'] as num?)?.toInt() ?? 0,
      cacheWrite: (usage['cacheWrite'] as num?)?.toInt() ?? 0,
      total: (usage['total'] as num?)?.toInt() ?? 0,
      model: model,
      provider: json['provider'] as String? ?? '',
    );

    // 持久化到 DB（关联到对应的 AI 消息）
    if (msgId != null && msgId.isNotEmpty) {
      _ref
          .read(messageDaoProvider)
          .updateTokenUsage(
            msgId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelName: model.isNotEmpty ? model : null,
          );
    }

    debugPrint(
      '[WsMessageHandler] Usage report: ${_ref.read(lastUsageReportProvider(convId))?.formattedLabel}',
    );
  }

  void _handleApprovalRequest(Map<String, dynamic> json) {
    final messageId = json['message_id'] as String? ?? 'approval_${DateTime.now().millisecondsSinceEpoch}';
    final convId = json['conversation_id'] as String? ?? json['account_id'] as String? ?? '';
    final command = json['command'] as String? ?? '';
    final description = json['description'] as String? ?? '';
    final patternKeys = (json['pattern_keys'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [];

    debugPrint('[WsMessageHandler] 🔐 approval_request: conv=$convId command="${command.length > 40 ? '${command.substring(0, 40)}...' : command}"');

    _ref.read(activeApprovalProvider.notifier).state = ApprovalRequest(
      messageId: messageId,
      conversationId: convId,
      command: command,
      description: description,
      patternKeys: patternKeys,
    );
  }

  void _handleClarifyRequest(Map<String, dynamic> json) {
    final messageId = json['message_id'] as String? ?? 'clarify_${DateTime.now().millisecondsSinceEpoch}';
    final convId = json['conversation_id'] as String? ?? json['account_id'] as String? ?? '';
    final question = json['question'] as String? ?? '';
    final choices = (json['choices'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [];

    debugPrint('[WsMessageHandler] ❓ clarify_request: conv=$convId question="${question.length > 40 ? '${question.substring(0, 40)}...' : question}"');

    _ref.read(activeClarifyProvider.notifier).state = ClarifyRequest(
      messageId: messageId,
      conversationId: convId,
      question: question,
      choices: choices,
    );
  }

  Future<void> _handleSystemStatus(SystemMessage msg) async {
    switch (msg.status) {
      case 'ai_connected':
        _ref.read(aiBackendStateProvider.notifier).state =
            AiBackendState.connected;
        final name = msg.agentName ?? 'Unknown';
        debugPrint(
          '[WsMessageHandler] ✅ AI connected: $name, accountId=${msg.accountId}',
        );
        // 追踪在线后端
        if (msg.accountId != null && msg.accountId!.isNotEmpty) {
          final accounts = _ref.read(connectedAccountsProvider);
          final exists = accounts.any((a) => a.accountId == msg.accountId);
          if (!exists) {
            _ref.read(connectedAccountsProvider.notifier).state = [
              ...accounts,
              ConnectedAccount(accountId: msg.accountId!, agentName: name),
            ];
          }
          // 会话由 Server 自动创建，客户端只需同步
          final convRepo = _ref.read(conversationRepositoryProvider);
          await convRepo.syncFromServer();
          // 如果当前没有选中会话，自动选中该 accountId 的第一个会话
          if (_ref.read(selectedConversationIdProvider) == null) {
            final convs = await convRepo.getConversationsByAccount(msg.accountId!);
            if (convs.isNotEmpty) {
              _ref.read(selectedConversationIdProvider.notifier).state = convs.first.conversationId;
            }
          }
        }
      case 'ai_disconnected':
        _ref.read(aiBackendStateProvider.notifier).state =
            AiBackendState.disconnected;
        // 从在线列表移除
        if (msg.accountId != null) {
          final accounts = _ref.read(connectedAccountsProvider);
          _ref.read(connectedAccountsProvider.notifier).state =
              accounts.where((a) => a.accountId != msg.accountId).toList();
        }
        debugPrint('[WsMessageHandler] ❌ AI backend disconnected: ${msg.accountId}');
      case 'stream_interrupted':
        _finalizeStreaming({});
        final detail = msg.message ?? 'Output may be incomplete';
        debugPrint('[WsMessageHandler] ⚠️ Stream interrupted: $detail');
      default:
        debugPrint('[WsMessageHandler] Unknown system_status: ${msg.status}');
    }
  }

  void _appendTextDelta(String messageId, String delta, String? accountId, String? conversationId) {
    debugPrint(
      '[WsHandler] 📥 text_delta: msgId=$messageId, len=${delta.length}, convId=${conversationId ?? accountId}',
    );
    final current = _ref.read(streamingMessageProvider);
    if (current != null && current.messageId != messageId) {
      // 新消息到达，先结束旧流 — 必须传入旧流的 conversationId
      // 否则 _finalizeStreaming 的 fallback 链会用错误的 convId
      _finalizeStreaming({
        'conversation_id': current.conversationId ?? _streamingConversationId,
        'account_id': _streamingAccountId,
      });
    }
    if (current == null || current.messageId != messageId) {
      // 首个 delta — 立即显示（不等 debounce）
      // waitingForReply 不在此清除 — isWaitingOnly 会自动失效（streamingMsg != null）
      _ref.read(activeToolProvider.notifier).state = null;  // 工具执行结束
      _streamingAccountId = accountId;
      _streamingConversationId = conversationId;
      _textBuffer = delta;
      _textBufferMsgId = messageId;
      final convId = conversationId ?? _streamingConversationId ?? accountId;
      _fl.log('[ROUTE] text_delta START: msgId=$messageId, convId=$convId, selected=${_ref.read(selectedConversationIdProvider)}');
      _ref.read(streamingMessageProvider.notifier).state = TextMessage(
        messageId: messageId,
        role: 'agent',
        content: delta,
        conversationId: convId,
      );
    } else {
      if (accountId != null) {
        _streamingAccountId = accountId;
      }
      if (conversationId != null) {
        _streamingConversationId = conversationId;
      }
      _textBuffer += delta;
      _textBufferMsgId = messageId;
      if (_enableDebounce) {
        // 节流：取消旧 Timer，启动新 Timer
        _textFlushTimer?.cancel();
        _textFlushTimer = Timer(
          Duration(milliseconds: _throttleMs(_textBuffer.length)),
          _flushTextBuffer,
        );
      } else {
        // 无 debounce：立即刷新
        _flushTextBuffer();
      }
    }
  }

  void _flushTextBuffer() {
    if (_textBufferMsgId == null) return;
    final existing = _ref.read(streamingMessageProvider);
    _ref.read(streamingMessageProvider.notifier).state = TextMessage(
      messageId: _textBufferMsgId!,
      role: 'agent',
      content: _textBuffer,
      conversationId: existing?.conversationId ?? _streamingConversationId,
    );
  }

  void _appendThinkingDelta(String messageId, String delta, String? accountId, String? conversationId) {
    debugPrint(
      '[WsHandler] 🧠 thinking_delta: msgId=$messageId, len=${delta.length}, convId=${conversationId ?? accountId}',
    );

    final current = _ref.read(streamingThinkingProvider);

    // 新会话的 thinking 到达，先结束旧流式文本（如有）
    final currentText = _ref.read(streamingMessageProvider);
    if (currentText != null && currentText.messageId != messageId.replaceFirst('think_', '')) {
      _finalizeStreaming({
        'conversation_id': currentText.conversationId ?? _streamingConversationId,
        'account_id': _streamingAccountId,
      });
    }

    // 在旧流结束后再更新会话标识
    if (accountId != null) _streamingAccountId = accountId;
    if (conversationId != null) _streamingConversationId = conversationId;
    final convId = conversationId ?? _streamingConversationId ?? accountId;

    if (current == null || current.messageId != messageId) {
      // 首个 delta — 立即显示
      // waitingForReply 不在此清除 — isWaitingOnly 会自动失效（streamingThinking != null）
      _thinkingBuffer = delta;
      _thinkingBufferMsgId = messageId;
      _ref.read(streamingThinkingProvider.notifier).state = ThinkingMessage(
        messageId: messageId,
        role: 'agent',
        content: delta,
        conversationId: convId,
      );
    } else {
      _thinkingBuffer += delta;
      _thinkingBufferMsgId = messageId;
      if (_enableDebounce) {
        _thinkingFlushTimer?.cancel();
        _thinkingFlushTimer = Timer(
          Duration(milliseconds: _throttleMs(_thinkingBuffer.length)),
          _flushThinkingBuffer,
        );
      } else {
        _flushThinkingBuffer();
      }
    }
  }

  void _flushThinkingBuffer() {
    if (_thinkingBufferMsgId == null) return;
    final existing = _ref.read(streamingThinkingProvider);
    _ref.read(streamingThinkingProvider.notifier).state = ThinkingMessage(
      messageId: _thinkingBufferMsgId!,
      role: 'agent',
      content: _thinkingBuffer,
      conversationId: existing?.conversationId ?? _streamingConversationId,
    );
  }

  void _finalizeThinking() {
    // thinking 完成后保留内容不清除，等 text_done 时一起清除
    // 这样 thinking 块会一直展示直到整条消息完成
  }

  /// 去重：上一次 finalize 的 serverMsgId（防止 Gateway 多轮 deliver 导致重复）
  String? _lastFinalizedServerMsgId;

  Future<void> _finalizeStreaming(Map<String, dynamic> json) async {
    // 去重：同一个 serverMsgId 只 finalize 一次
    final serverMsgId = json['message_id'] as String?;
    if (serverMsgId != null && serverMsgId == _lastFinalizedServerMsgId) {
      debugPrint('[WsHandler] ⏭️ _finalizeStreaming SKIP duplicate: $serverMsgId');
      return;
    }
    _lastFinalizedServerMsgId = serverMsgId;

    // 强制刷新缓冲区，确保最后的 delta 不丢失
    _textFlushTimer?.cancel();
    _flushTextBuffer();
    _thinkingFlushTimer?.cancel();
    _flushThinkingBuffer();

    final msg = _ref.read(streamingMessageProvider);
    final thinkingMsg = _ref.read(streamingThinkingProvider);

    if (msg != null || thinkingMsg != null) {
      // conversationId 优先级：
      // 1. text_done JSON 中的 conversation_id（服务端权威值）
      // 2. 流式消息本身携带的 conversationId（首个 delta 设置，最可靠）
      // 3. _streamingConversationId（delta 过程中跟踪，可能被覆盖）
      // 4. JSON 中的 account_id
      // 5. 当前选中的会话（最后手段，极易出错）
      final convId =
          json['conversation_id'] as String? ??
          msg?.conversationId ??
          thinkingMsg?.conversationId ??
          _streamingConversationId ??
          json['account_id'] as String? ??
          _ref.read(selectedConversationIdProvider) ??
          'default';
      final accountId =
          json['account_id'] as String? ??
          _streamingAccountId ??
          convId;

      debugPrint(
        '[WsHandler] ✅ _finalizeStreaming: msgId=${msg?.messageId ?? thinkingMsg?.messageId}, '
        'convId=$convId, jsonConvId=${json['conversation_id']}, '
        'streamConvId=$_streamingConversationId, '
        'msgConvId=${msg?.conversationId}, selected=${_ref.read(selectedConversationIdProvider)}',
      );
      _fl.log('[ROUTE] FINALIZE: msgId=${msg?.messageId ?? thinkingMsg?.messageId}, '
        'convId=$convId, jsonConvId=${json['conversation_id']}, '
        'streamConvId=$_streamingConversationId, '
        'msgConvId=${msg?.conversationId}, selected=${_ref.read(selectedConversationIdProvider)}');

      _streamingAccountId = null;
      _streamingConversationId = null;

      // 尝试从 provider 提取回退的 messageId
      final safeMessageId =
          json['message_id'] as String? ??
          msg?.messageId ??
          thinkingMsg?.messageId ??
          'aborted_${DateTime.now().millisecondsSinceEpoch}';

      final serverMsgId = json['message_id'] as String?;
      final seq = json['seq'] as int? ?? 0;
      if (seq > 0) _advanceSyncSeq(seq);

      // 如果 text_done 携带 error_code，用翻译后的文案替换空内容
      var finalContent = msg?.content ?? '';
      final errorCode = json['error_code'] as String?;
      if (errorCode != null && finalContent.trim().isEmpty) {
        final errorDetail = json['error_detail'] as String? ?? '';
        finalContent = _translateErrorCode(errorCode, errorDetail);
      }

      await _ref
          .read(messageRepositoryProvider)
          .receiveMessage(
            messageId: safeMessageId,
            accountId: accountId,
            conversationId: convId,
            senderId: 'agent',
            type: 'text',
            content: finalContent,
            thinkingContent: thinkingMsg?.content,
            serverId: serverMsgId,
            seq: seq,
            createdAt: json['created_at'] as int?,
          );
      if (convId == _ref.read(selectedConversationIdProvider)) {
        _ref.read(conversationRepositoryProvider).markAsRead(convId);
      }

      // DB 写入完成后清除流式状态
      _ref.read(waitingForReplyProvider.notifier).state = null;
      _ref.read(activeToolProvider.notifier).state = null;
      _ref.read(streamingMessageProvider.notifier).state = null;
      // 让出事件循环，等 Drift watchMessages 流通知 UI 刷新后再清 thinking → 无闪烁
      await Future<void>.delayed(Duration.zero);
      _ref.read(streamingThinkingProvider.notifier).state = null;

      // 重置 debounce 缓冲区
      _textBuffer = '';
      _textBufferMsgId = null;
      _thinkingBuffer = '';
      _thinkingBufferMsgId = null;
    }
  }

  /// 将 Gateway 的 error_code 翻译为用户可读的本地化文案
  String _translateErrorCode(String errorCode, String detail) {
    final locale = _ref.read(localeProvider) ?? const Locale('en');
    final l10n = lookupAppLocalizations(locale);

    switch (errorCode) {
      case 'auth_failed':
        return l10n.errorAuthFailed;
      case 'network_error':
        return l10n.errorNetworkError;
      case 'rate_limited':
        return l10n.errorRateLimited;
      case 'model_unavailable':
        return l10n.errorModelUnavailable;
      case 'no_reply':
        return l10n.errorNoReply;
      case 'agent_error':
      default:
        return l10n.errorAgentError(detail.isNotEmpty ? detail : 'unknown');
    }
  }

  Future<void> _writeToDb(MessageModel model, Map<String, dynamic> json) async {
    final convId =
        json['conversation_id'] as String? ??
        json['account_id'] as String? ??
        _ref.read(selectedConversationIdProvider) ??
        'default';
    final accountId =
        json['account_id'] as String? ?? convId;
    final serverMsgId = json['message_id'] as String?;
    final seq = json['seq'] as int? ?? 0;
    if (seq > 0) _advanceSyncSeq(seq);
    final repo = _ref.read(messageRepositoryProvider);

    switch (model) {
      case TextMessage m:
        await repo.receiveMessage(
          messageId: m.messageId,
          accountId: accountId,
          conversationId: convId,
          senderId: 'agent',
          type: 'text',
          content: m.content,
          serverId: serverMsgId,
          seq: seq,
          createdAt: json['created_at'] as int?,
        );
      case SduiMessage m:
        // 拦截全局页面组件（路由到对应的导航页面，不写入对话流）
        final navPage = _widgetToNavPage(m.component.widgetName);
        if (navPage != null) {
          final cache = Map<NavPage, SduiMessage?>.from(
            _ref.read(sduiPageCacheProvider),
          );
          cache[navPage] = m;
          _ref.read(sduiPageCacheProvider.notifier).state = cache;
          // 自动切换到对应页面
          _ref.read(activeNavPageProvider.notifier).state = navPage;
          return;
        }

        await repo.receiveMessage(
          messageId: m.messageId,
          accountId: accountId,
          conversationId: convId,
          senderId: 'agent',
          type: 'cup_component',
          content: jsonEncode(m.component.toJson()),
          serverId: serverMsgId,
          seq: seq,
          createdAt: json['created_at'] as int?,
        );
      case ErrorMessage m:
        await repo.receiveMessage(
          messageId: m.messageId,
          accountId: accountId,
          conversationId: convId,
          senderId: 'system',
          type: 'system',
          content: 'Unknown widget: ${m.widgetName}',
          serverId: serverMsgId,
          seq: seq,
          createdAt: json['created_at'] as int?,
        );
      case SystemMessage _:
        break;
      case ThinkingMessage _:
        break; // thinking 内容不持久化到 DB
    }

    if (convId == _ref.read(selectedConversationIdProvider)) {
      _ref.read(conversationRepositoryProvider).markAsRead(convId);
    }
    if (convId != _ref.read(selectedConversationIdProvider)) {
      NotificationService.showMessageNotification(
        title: '新消息',
        body: _getNotificationBody(model),
        accountId: convId,
      );
    }
  }

  String _getNotificationBody(MessageModel model) {
    return switch (model) {
      TextMessage m =>
        m.content.length > 100
            ? '${m.content.substring(0, 100)}...'
            : m.content,
      SduiMessage _ => '[富组件消息]',
      ErrorMessage _ => '[系统提示]',
      SystemMessage m => m.message ?? '系统通知',
      ThinkingMessage _ => '[AI 推理中]',
    };
  }

  /// 将 widget 名称映射到导航页面
  static NavPage? _widgetToNavPage(String widgetName) {
    return switch (widgetName) {
      'DashboardView' => NavPage.dashboard,
      'CronListView' => NavPage.cron,
      'ChannelsView' || 'ChannelConnectDialog' => NavPage.channels,
      'SkillsView' || 'SkillConfigDialog' => NavPage.skills,
      _ => null,
    };
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _textFlushTimer?.cancel();
    _thinkingFlushTimer?.cancel();
    _streamingAccountId = null;
    _streamingConversationId = null;
    _ws.onConnected = null;
  }
}

// 新版消息列表 — Drift .watch() 驱动 + 响应式 Limit 分页
final chatMessagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  accountId,
) {
  ref.watch(wsMessageHandlerProvider);
  final limit = ref.watch(chatLimitProvider(accountId));
  return ref
      .watch(messageRepositoryProvider)
      .watchMessages(accountId, limit: limit);
});
