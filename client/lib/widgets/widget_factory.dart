import 'package:flutter/widgets.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/widgets/markdown_widget.dart';
import 'package:client/widgets/code_editor_widget.dart';
import 'package:client/widgets/upgrade_prompt_widget.dart';
import 'package:client/widgets/dashboard_view.dart';
import 'package:client/widgets/sdui/cron_list_view.dart';
import 'package:client/widgets/sdui/channels_view.dart';
import 'package:client/widgets/sdui/channel_connect_dialog.dart';
import 'package:client/widgets/sdui/skills_view.dart';
import 'package:client/widgets/sdui/skill_config_dialog.dart';

class WidgetFactory {
  static Widget build(SduiComponentModel component, String messageId) {
    return switch (component.widgetName) {
      'MarkdownView' => MarkdownWidget(
          props: component.props,
          actions: component.actions,
          messageId: messageId,
        ),
      'CodeEditorView' => CodeEditorWidget(
          props: component.props,
          actions: component.actions,
          messageId: messageId,
        ),
      'DashboardView' => DashboardView(
          component: component,
        ),
      'CronListView' => CronListView(
          props: component.props,
          messageId: messageId,
        ),
      'ChannelsView' => ChannelsView(
          props: component.props,
          messageId: messageId,
        ),
      'ChannelConnectDialog' => ChannelConnectDialog(
          props: component.props,
          messageId: messageId,
        ),
      'SkillsView' => SkillsView(props: component.props, messageId: messageId),
      'SkillConfigDialog' => SkillConfigDialog(
          props: component.props,
          messageId: messageId,
        ),
      _ => UpgradePromptWidget(unknownWidgetName: component.widgetName),
    };
  }
}
