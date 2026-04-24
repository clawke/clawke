import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 审批请求数据（Gateway → Client）
class ApprovalRequest {
  final String messageId;
  final String conversationId;
  final String command;
  final String description;
  final List<String> patternKeys;

  const ApprovalRequest({
    required this.messageId,
    required this.conversationId,
    required this.command,
    required this.description,
    this.patternKeys = const [],
  });
}

/// 澄清请求数据（Gateway → Client）
class ClarifyRequest {
  final String messageId;
  final String conversationId;
  final String question;
  final List<String> choices;

  const ClarifyRequest({
    required this.messageId,
    required this.conversationId,
    required this.question,
    this.choices = const [],
  });
}

/// 当前活跃的审批请求（ephemeral，不持久化）
final activeApprovalProvider = StateProvider<ApprovalRequest?>((ref) => null);

/// 当前活跃的澄清请求（ephemeral，不持久化）
final activeClarifyProvider = StateProvider<ClarifyRequest?>((ref) => null);
