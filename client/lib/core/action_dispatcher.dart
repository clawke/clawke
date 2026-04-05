import 'dart:convert';
import 'package:client/core/ws_service.dart';
import 'package:client/models/sdui_component_model.dart';

class ActionDispatcher {
  final WsService _ws;
  ActionDispatcher(this._ws);

  void dispatch({
    required String sessionId,
    required String messageId,
    required ActionModel action,
    required Map<String, dynamic> data,
  }) {
    final event = {
      'protocol': 'clawke_event_v1',
      'event_type': 'user_action',
      'context': {'session_id': sessionId, 'message_id': messageId},
      'action': {
        'action_id': action.actionId,
        'trigger': 'button_click',
        'data': data,
      },
    };
    _ws.send(jsonEncode(event));
  }
}
