import 'package:client/models/message_model.dart';
import 'package:client/models/sdui_component_model.dart';

class CupParser {
  static MessageModel? parse(Map<String, dynamic> json) {
    try {
      final payloadType = json['payload_type'] as String? ?? '';
      final messageId =
          json['message_id'] as String? ??
          'unknown_${DateTime.now().millisecondsSinceEpoch}';

      switch (payloadType) {
        case 'text_delta':
          return TextMessage(
            messageId: messageId,
            role: 'agent',
            content: json['content'] as String? ?? '',
          );
        case 'text_done':
          return null;
        case 'thinking_delta':
          return ThinkingMessage(
            messageId: messageId,
            role: 'agent',
            content: json['content'] as String? ?? '',
          );
        case 'thinking_done':
          return null;
        case 'ui_component':
          final componentJson = json['component'] as Map<String, dynamic>?;
          if (componentJson == null) return null;
          return SduiMessage(
            messageId: messageId,
            role: json['role'] as String? ?? 'agent',
            component: SduiComponentModel.fromJson(componentJson),
          );
        case 'system_status':
          return SystemMessage(
            messageId: messageId,
            role: 'system',
            status: json['status'] as String? ?? '',
            agentName: json['agent_name'] as String?,
            message: json['message'] as String?,
            accountId: json['account_id'] as String?,
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  static bool isTextDone(Map<String, dynamic> json) =>
      json['payload_type'] == 'text_done';

  static bool isTextDelta(Map<String, dynamic> json) =>
      json['payload_type'] == 'text_delta';

  static bool isThinkingDelta(Map<String, dynamic> json) =>
      json['payload_type'] == 'thinking_delta';

  static bool isThinkingDone(Map<String, dynamic> json) =>
      json['payload_type'] == 'thinking_done';

  static bool isApprovalRequest(Map<String, dynamic> json) =>
      json['payload_type'] == 'approval_request';

  static bool isClarifyRequest(Map<String, dynamic> json) =>
      json['payload_type'] == 'clarify_request';
}
