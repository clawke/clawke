/// CUP 协议 JSON 工厂方法 — 所有测试文件的唯一数据源
library;

Map<String, dynamic> makeTextDelta({
  String messageId = 'msg_001',
  String content = 'Hello, world!',
}) => {
  'payload_type': 'text_delta',
  'message_id': messageId,
  'content': content,
};

Map<String, dynamic> makeTextDone({String messageId = 'msg_001'}) => {
  'payload_type': 'text_done',
  'message_id': messageId,
};

Map<String, dynamic> makeUiComponent({
  String messageId = 'msg_002',
  String role = 'agent',
  String widgetName = 'MarkdownView',
  Map<String, dynamic> props = const {'content': '# Hello'},
  List<Map<String, dynamic>>? actions,
}) => {
  'payload_type': 'ui_component',
  'message_id': messageId,
  'role': role,
  'component': {
    'widget_name': widgetName,
    'props': props,
    'actions':
        actions ??
        [
          {'action_id': 'cmd_copy', 'label': '复制', 'type': 'local'},
        ],
  },
};

Map<String, dynamic> makeSystemStatus({
  String messageId = 'msg_003',
  String status = 'ai_connected',
  String? agentName,
  String? message,
}) => {
  'payload_type': 'system_status',
  'message_id': messageId,
  'status': status,
  if (agentName != null) 'agent_name': agentName,
  if (message != null) 'message': message,
};

Map<String, dynamic> makeAction({
  String actionId = 'cmd_copy',
  String label = '复制',
  String type = 'local',
}) => {'action_id': actionId, 'label': label, 'type': type};

/// 畸形 component — 用于测试 catch 分支（props 不是 Map）
Map<String, dynamic> makeMalformedComponent({String messageId = 'msg_bad'}) => {
  'payload_type': 'ui_component',
  'message_id': messageId,
  'component': {
    'widget_name': 123, // 非 String，触发 TypeError
    'props': 'not_a_map',
    'actions': 'not_a_list',
  },
};

Map<String, dynamic> makeThinkingDelta({
  String messageId = 'msg_think_001',
  String content = '让我分析一下...',
}) => {
  'payload_type': 'thinking_delta',
  'message_id': messageId,
  'content': content,
};

Map<String, dynamic> makeThinkingDone({String messageId = 'msg_think_001'}) => {
  'payload_type': 'thinking_done',
  'message_id': messageId,
};
