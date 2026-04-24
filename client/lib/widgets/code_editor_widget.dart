import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/core/action_dispatcher.dart' as core;
import 'package:client/providers/ws_state_provider.dart';

class CodeEditorWidget extends ConsumerWidget {
  final Map<String, dynamic> props;
  final List<ActionModel> actions;
  final String messageId;

  const CodeEditorWidget({
    super.key,
    required this.props,
    required this.actions,
    required this.messageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = props['language'] as String? ?? 'plaintext';
    final filename = props['filename'] as String? ?? 'unknown';
    final content = props['content'] as String? ?? '';
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部文件名 bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  filename,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  language,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                  ),
                ),
              ],
            ),
          ),
          // 代码内容区：ConstrainedBox 防止嵌套滚动崩溃
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: SingleChildScrollView(
              child: HighlightView(
                content,
                language: language,
                theme: isDark ? monokaiSublimeTheme : githubTheme,
                padding: const EdgeInsets.all(12),
                textStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                ),
              ),
            ),
          ),
          // Action 操作区
          if (actions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                children: actions
                    .map(
                      (action) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: OutlinedButton(
                          onPressed: () =>
                              _handleAction(ref, action, content, filename),
                          child: Text(action.label),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  void _handleAction(
    WidgetRef ref,
    ActionModel action,
    String content,
    String filename,
  ) {
    if (action.type == 'local') {
      Clipboard.setData(ClipboardData(text: content));
    } else {
      final ws = ref.read(wsServiceProvider);
      core.ActionDispatcher(ws).dispatch(
        sessionId: 'sess_mvp',
        messageId: messageId,
        action: action,
        data: {'filename': filename, 'content': content},
      );
    }
  }
}
