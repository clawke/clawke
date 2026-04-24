import 'package:client/models/sdui_component_model.dart';

sealed class MessageModel {
  final String messageId;
  final String role;
  const MessageModel({required this.messageId, required this.role});
}

class TextMessage extends MessageModel {
  final String content;
  /// 多会话路由：流式消息所属的 conversationId
  final String? conversationId;
  const TextMessage({
    required super.messageId,
    required super.role,
    required this.content,
    this.conversationId,
  });

  TextMessage copyWith({String? content, String? conversationId}) => TextMessage(
    messageId: messageId,
    role: role,
    content: content ?? this.content,
    conversationId: conversationId ?? this.conversationId,
  );
}

class SduiMessage extends MessageModel {
  final SduiComponentModel component;
  const SduiMessage({
    required super.messageId,
    required super.role,
    required this.component,
  });
}

class ErrorMessage extends MessageModel {
  final String widgetName;
  const ErrorMessage({
    required super.messageId,
    required super.role,
    required this.widgetName,
  });
}

class SystemMessage extends MessageModel {
  final String
  status; // 'ai_connected' | 'ai_disconnected' | 'stream_interrupted'
  final String? agentName;
  final String? message;
  final String? accountId;

  const SystemMessage({
    required super.messageId,
    required super.role,
    required this.status,
    this.agentName,
    this.message,
    this.accountId,
  });
}

class ThinkingMessage extends MessageModel {
  final String content;
  final String? conversationId;
  const ThinkingMessage({
    required super.messageId,
    required super.role,
    required this.content,
    this.conversationId,
  });

  ThinkingMessage copyWith({String? content, String? conversationId}) => ThinkingMessage(
    messageId: messageId,
    role: role,
    content: content ?? this.content,
    conversationId: conversationId ?? this.conversationId,
  );
}
