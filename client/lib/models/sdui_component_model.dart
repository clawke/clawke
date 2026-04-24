class ActionModel {
  final String actionId;
  final String label;
  final String type; // "local" | "remote"

  const ActionModel({
    required this.actionId,
    required this.label,
    required this.type,
  });

  factory ActionModel.fromJson(Map<String, dynamic> json) => ActionModel(
    actionId: json['action_id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    type: json['type'] as String? ?? 'local',
  );

  Map<String, dynamic> toJson() => {
    'action_id': actionId,
    'label': label,
    'type': type,
  };
}

class SduiComponentModel {
  final String widgetName;
  final Map<String, dynamic> props;
  final List<ActionModel> actions;

  const SduiComponentModel({
    required this.widgetName,
    required this.props,
    required this.actions,
  });

  factory SduiComponentModel.fromJson(Map<String, dynamic> json) =>
      SduiComponentModel(
        widgetName: json['widget_name'] as String? ?? 'UnknownWidget',
        props: (json['props'] as Map<String, dynamic>?) ?? {},
        actions: ((json['actions'] as List<dynamic>?) ?? [])
            .map((a) => ActionModel.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'widget_name': widgetName,
    'props': props,
    'actions': actions.map((a) => a.toJson()).toList(),
  };
}
