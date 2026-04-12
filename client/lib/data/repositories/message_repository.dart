import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/data/database/dao/message_dao.dart';
import 'package:client/data/database/dao/conversation_dao.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/services/media_cache_service.dart';
import 'package:client/services/media_upload_service.dart';
import 'package:client/services/media_resolver.dart';


/// Current device unique ID (hostname + platform) for multi-device sync
String get deviceId => '${Platform.localHostname}_${Platform.operatingSystem}';

const _uuid = Uuid();

/// 发送消息的结果
class SendResult {
  final String requestId;
  final String clientMsgId;
  const SendResult({required this.requestId, required this.clientMsgId});
}

class MessageRepository {
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;
  final WsService _ws;

  MessageRepository({
    required MessageDao messageDao,
    required ConversationDao conversationDao,
    required WsService ws,
  }) : _messageDao = messageDao,
       _conversationDao = conversationDao,
       _ws = ws;

  /// 监听流 — UI 用这个
  Stream<List<Message>> watchMessages(String conversationId, {int limit = 50}) {
    return _messageDao.watchMessages(conversationId, limit: limit);
  }

  /// 写入流 — 收到消息时调用
  Future<void> receiveMessage({
    required String messageId,
    required String accountId,
    String? conversationId,
    required String senderId,
    required String type,
    required String content,
    String? serverId,
    String? quoteId,
    String? thinkingContent,
    int seq = 0,
    int? createdAt,
  }) async {
    final convId = conversationId ?? accountId;
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;

    await _messageDao.insertMessage(
      MessagesCompanion(
        messageId: Value(messageId),
        serverId: Value(serverId),
        accountId: Value(accountId),
        conversationId: Value(convId),
        senderId: Value(senderId),
        type: Value(type),
        content: Value(content),
        thinkingContent: Value(thinkingContent),
        quoteId: Value(quoteId),
        status: const Value('sent'),
        seq: Value(seq),
        createdAt: Value(now),
      ),
    );

    // 更新会话的最后一条消息
    await _conversationDao.updateLastMessage(
      conversationId: convId,
      messageId: messageId,
      messageAt: now,
      preview: _generatePreview(type, content),
    );

    // 未读 +1（不是自己发的才加）
    await _conversationDao.incrementUnseenCount(convId);
  }

  /// 发消息 — 等服务端 ACK 后才标记 sent
  /// 返回 SendResult，用于关联 ACK
  SendResult sendMessage({
    required String accountId,
    required String conversationId,
    required String content,
    required String senderId,
    String type = 'text',
    String? quoteId,
  }) {
    final messageId = 'cmsg_${_uuid.v4()}';
    final requestId = 'req_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 先写入本地 DB（status = sending）→ 线 2 自动更新 UI
    _messageDao.insertMessage(
      MessagesCompanion(
        messageId: Value(messageId),
        accountId: Value(accountId),
        conversationId: Value(conversationId),
        senderId: Value(senderId),
        type: Value(type),
        content: Value(content),
        quoteId: Value(quoteId),
        status: const Value('sending'),
        createdAt: Value(now),
      ),
    );

    // 更新会话预览
    _conversationDao.updateLastMessage(
      conversationId: conversationId,
      messageId: messageId,
      messageAt: now,
      preview: _generatePreview(type, content),
    );

    // 2. 发送到网络（不标 sent，等 ACK）
    try {
      _ws.sendJson({
        'id': requestId,
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': accountId,
          'conversation_id': conversationId,
          'client_msg_id': messageId,
        },
        'data': {
          'content': content,
          'type': type,
          if (quoteId != null) 'quote_id': quoteId,
        },
      });
    } catch (e) {
      _messageDao.updateStatus(messageId, 'failed');
    }

    return SendResult(requestId: requestId, clientMsgId: messageId);
  }

  /// 重试失败消息，返回 SendResult
  Future<SendResult?> retryMessage(String messageId) async {
    final msg = await _messageDao.getMessage(messageId);
    if (msg == null || msg.status != 'failed') return null;

    final requestId = 'req_${_uuid.v4().substring(0, 8)}';

    await _messageDao.updateStatus(messageId, 'sending');
    try {
      _ws.sendJson({
        'id': requestId,
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': msg.accountId,
          'conversation_id': msg.conversationId,
          'client_msg_id': messageId,
        },
        'data': {'content': msg.content ?? '', 'type': msg.type},
      });
    } catch (e) {
      await _messageDao.updateStatus(messageId, 'failed');
      return null;
    }

    return SendResult(requestId: requestId, clientMsgId: messageId);
  }

  /// 编辑消息
  Future<void> editMessage(String messageId, String newContent) async {
    await _messageDao.updateContent(messageId, newContent);
    // TODO: 通知服务端
  }

  /// 软删除消息
  Future<void> deleteMessage(String messageId) async {
    await _messageDao.softDelete(messageId);
    // TODO: 通知服务端
  }

  /// 清空会话中的所有消息
  Future<void> clearConversation(String conversationId) async {
    await _messageDao.deleteByConversation(conversationId);
    // 重置会话的最后消息信息
    await _conversationDao.updateLastMessage(
      conversationId: conversationId,
      messageId: '',
      messageAt: DateTime.now().millisecondsSinceEpoch,
      preview: '',
    );
  }

  /// 发送图片消息（HTTP 上传 + WS 消息引用）
  ///
  /// 流程：
  /// 1. HTTP POST 上传文件到 CS -> 获取 mediaUrl, thumbUrl, thumbHash
  /// 2. WS 发送轻量消息引用 URL（不含文件内容）
  Future<SendResult> sendImageMessage({
    required String accountId,
    required String conversationId,
    required String senderId,
    required String filePath,
    void Function(String messageId, double progress)? onProgress,
  }) async {
    final messageId = 'cmsg_${_uuid.v4()}';
    final requestId = 'req_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final fileName = p.basename(filePath);

    // IM 标准模式：复制到 App 缓存目录，确保后续可访问
    final cachedPath = MediaCacheService.instance.cacheFileSync(filePath);

    debugPrint(
      '[MessageRepo] 发送图片: path=$filePath, cached=$cachedPath, msgId=$messageId',
    );

    // 本地 DB 先存缓存路径（确保渲染时可访问）
    _messageDao.insertMessage(
      MessagesCompanion(
        messageId: Value(messageId),
        accountId: Value(accountId),
        conversationId: Value(conversationId),
        senderId: Value(senderId),
        type: const Value('image'),
        content: Value(cachedPath),
        status: const Value('sending'),
        createdAt: Value(now),
      ),
    );

    _conversationDao.updateLastMessage(
      conversationId: conversationId,
      messageId: messageId,
      messageAt: now,
      preview: '[图片]',
    );

    try {
      // 1. HTTP upload to CS
      final uploadService = MediaUploadService(baseUrl: MediaResolver.baseUrl);
      final result = await uploadService.upload(
        File(cachedPath),
        onProgress: onProgress != null ? (p) => onProgress(messageId, p) : null,
      );
      debugPrint('[MessageRepo] HTTP upload OK: ${result.mediaUrl}');

      // 更新 DB content：从本地路径 → JSON 格式（与 message_echo 一致）
      // 这样自己发的图片也走 ProgressiveImage 新架构查看器
      final contentJson = jsonEncode({
        'mediaUrl': result.mediaUrl,
        'thumbUrl': result.thumbUrl,
        'thumbHash': result.thumbHash,
        'width': result.width,
        'height': result.height,
        'fileName': fileName,
        'localPath': cachedPath, // 保留本地缓存路径，避免重复下载
      });
      _messageDao.updateContent(messageId, contentJson);

      // 2. WS: lightweight message reference (no file content, just URL)
      _ws.sendJson({
        'id': requestId,
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': accountId,
          'conversation_id': conversationId,
          'client_msg_id': messageId,
          'device_id': deviceId,
        },
        'data': {
          'type': 'image',
          'mediaUrl': result.mediaUrl,
          'thumbUrl': result.thumbUrl,
          'thumbHash': result.thumbHash,
          'width': result.width,
          'height': result.height,
          'fileName': fileName,
        },
      });
      debugPrint('[MessageRepo] Image message sent to server: $requestId');
    } catch (e) {
      debugPrint('[MessageRepo] Image message send failed: $e');
      _messageDao.updateStatus(messageId, 'failed');
    }

    return SendResult(requestId: requestId, clientMsgId: messageId);
  }

  /// 发送文件消息（HTTP 上传 + WS 消息引用）
  ///
  /// 流程（同 sendImageMessage）：
  /// 1. HTTP POST 上传文件到 CS -> 获取 mediaUrl
  /// 2. WS 发送轻量消息引用 URL（不含文件内容）
  Future<SendResult> sendFileMessage({
    required String accountId,
    required String conversationId,
    required String senderId,
    required String filePath,
    required String fileName,
    int? fileSize,
    void Function(String messageId, double progress)? onProgress,
  }) async {
    final messageId = 'cmsg_${_uuid.v4()}';
    final requestId = 'req_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().millisecondsSinceEpoch;

    // IM 标准模式：复制到 App 缓存目录（同 sendImageMessage）
    final savedPath = MediaCacheService.instance.cacheFileSync(filePath);
    debugPrint(
      '[MessageRepo] 发送文件: name=$fileName, 原路径=$filePath, 保存路径=$savedPath, size=$fileSize, msgId=$messageId',
    );

    // content 存 JSON
    final contentJson = jsonEncode({
      'path': savedPath,
      'name': fileName,
      'size': fileSize ?? 0,
    });

    _messageDao.insertMessage(
      MessagesCompanion(
        messageId: Value(messageId),
        accountId: Value(accountId),
        conversationId: Value(conversationId),
        senderId: Value(senderId),
        type: const Value('file'),
        content: Value(contentJson),
        status: const Value('sending'),
        createdAt: Value(now),
      ),
    );

    _conversationDao.updateLastMessage(
      conversationId: conversationId,
      messageId: messageId,
      messageAt: now,
      preview: '[文件] $fileName',
    );

    try {
      // 1. HTTP upload to CS（同 sendImageMessage）
      final uploadService = MediaUploadService(baseUrl: MediaResolver.baseUrl);
      final result = await uploadService.upload(
        File(savedPath),
        onProgress: onProgress != null ? (p) => onProgress(messageId, p) : null,
      );
      debugPrint('[MessageRepo] File HTTP upload OK: ${result.mediaUrl}');

      // 更新 DB content：从本地路径 → JSON 格式（与 sendImageMessage 一致）
      final updatedContentJson = jsonEncode({
        'mediaUrl': result.mediaUrl,
        'mediaType': result.mediaType ?? 'application/octet-stream',
        'name': fileName,
        'size': fileSize ?? 0,
        'localPath': savedPath,  // 发送端本地路径
      });
      _messageDao.updateContent(messageId, updatedContentJson);

      // 2. WS: lightweight message reference (no file content, just URL)
      _ws.sendJson({
        'id': requestId,
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': accountId,
          'conversation_id': conversationId,
          'client_msg_id': messageId,
          'device_id': deviceId,
        },
        'data': {
          'type': 'file',
          'mediaUrl': result.mediaUrl,
          'mediaType': result.mediaType ?? 'application/octet-stream',
          'fileName': fileName,
          'fileSize': fileSize,
        },
      });
      debugPrint('[MessageRepo] File message sent to server: $requestId');
    } catch (e) {
      debugPrint('[MessageRepo] File message send failed: $e');
      _messageDao.updateStatus(messageId, 'failed');
    }

    return SendResult(requestId: requestId, clientMsgId: messageId);
  }

  /// 发送混合消息 — Phase 1：立即写入 DB（本地路径），消息瞬间出现在聊天窗口
  ///
  /// 返回 SendResult，调用方后续用 [finalizeMixed] 更新为上传后的内容并发送 WS。
  SendResult insertMixedLocal({
    required String accountId,
    required String conversationId,
    required String senderId,
    required String contentJson,
    String? quoteId,
  }) {
    final messageId = 'cmsg_${_uuid.v4()}';
    final requestId = 'req_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().millisecondsSinceEpoch;

    _messageDao.insertMessage(
      MessagesCompanion(
        messageId: Value(messageId),
        accountId: Value(accountId),
        conversationId: Value(conversationId),
        senderId: Value(senderId),
        type: const Value('mixed'),
        content: Value(contentJson),
        quoteId: Value(quoteId),
        status: const Value('sending'),
        createdAt: Value(now),
      ),
    );

    _conversationDao.updateLastMessage(
      conversationId: conversationId,
      messageId: messageId,
      messageAt: now,
      preview: _generatePreview('mixed', contentJson),
    );

    return SendResult(requestId: requestId, clientMsgId: messageId);
  }

  /// 发送混合消息 — Phase 2：HTTP 上传完成后，更新 DB content + 发送 WS
  void finalizeMixed({
    required String messageId,
    required String requestId,
    required String accountId,
    required String conversationId,
    required String contentJson,
    String? quoteId,
  }) {
    // DB 保留 localPath（本地缓存路径）
    _messageDao.updateContent(messageId, contentJson);

    // WS 发送时剥离 localPath/path（本地路径不应广播给其他客户端）
    final wsContent = _stripLocalPaths(contentJson);

    try {
      _ws.sendJson({
        'id': requestId,
        'protocol': 'cup_v2',
        'event_type': 'user_message',
        'context': {
          'account_id': accountId,
          'conversation_id': conversationId,
          'client_msg_id': messageId,
          'device_id': deviceId,
        },
        'data': {
          'content': wsContent,
          'type': 'mixed',
          if (quoteId != null) 'quote_id': quoteId,
        },
      });
    } catch (e) {
      _messageDao.updateStatus(messageId, 'failed');
    }
  }

  /// 从 mixed JSON 的 attachments 中移除本地路径字段
  String _stripLocalPaths(String contentJson) {
    try {
      final data = Map<String, dynamic>.from(
        jsonDecode(contentJson) as Map,
      );
      final attachments = data['attachments'] as List<dynamic>?;
      if (attachments != null) {
        for (final att in attachments) {
          if (att is Map<String, dynamic>) {
            att.remove('localPath');
            att.remove('path');
          }
        }
      }
      return jsonEncode(data);
    } catch (_) {
      return contentJson;
    }
  }



  String _generatePreview(String type, String? content) {
    return switch (type) {
      'text' =>
        (content ?? '').length > 50
            ? '${content!.substring(0, 50)}...'
            : content ?? '',
      'image' => '[图片]',
      'file' => '[文件]',
      'mixed' => _generateMixedPreview(content),
      'voice' => '[语音]',
      _ => '[消息]',
    };
  }

  String _generateMixedPreview(String? content) {
    if (content == null) return '[消息]';
    try {
      final data = Map<String, dynamic>.from(
        const JsonDecoder().convert(content) as Map,
      );
      final text = data['text'] as String? ?? '';
      final attachments = (data['attachments'] as List?)?.length ?? 0;
      final prefix = attachments > 0 ? '[$attachments个附件]' : '';
      if (text.isNotEmpty) {
        final preview = text.length > 30 ? '${text.substring(0, 30)}...' : text;
        return '$prefix $preview'.trim();
      }
      return prefix.isNotEmpty ? prefix : '[消息]';
    } catch (_) {
      return '[消息]';
    }
  }
}
