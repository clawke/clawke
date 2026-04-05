import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:client/widgets/highlighted_code_builder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/providers/ws_state_provider.dart';

/// 匹配裸 URL（不在 markdown 链接 `](...)` 和代码块内的 http/https 链接）
final _bareUrlRegex = RegExp(
  r'(?<!\]\()(?<!\()(https?://[^\s\)\]>]+)',
);

class MarkdownWidget extends ConsumerWidget {
  final Map<String, dynamic> props;
  final List<ActionModel> actions;
  final String messageId;

  const MarkdownWidget({
    super.key,
    required this.props,
    required this.actions,
    required this.messageId,
  });

  /// 将裸 URL 转换为 markdown 链接语法
  ///
  /// 例如：`https://www.douyin.com/` → `[https://www.douyin.com/](https://www.douyin.com/)`
  /// 已经在 `[text](url)` 内的链接不会被重复包装。
  static String _autoLinkUrls(String content) {
    // 跳过代码块中的 URL：先提取代码块，替换为占位符，处理完再还原
    final codeBlocks = <String>[];
    var processed = content.replaceAllMapped(
      RegExp(r'```[\s\S]*?```|`[^`]+`'),
      (match) {
        codeBlocks.add(match.group(0)!);
        return '\x00CODE${codeBlocks.length - 1}\x00';
      },
    );

    // 先处理 <URL> 角括号自动链接语法：剥离角括号，交给后续裸 URL 处理
    processed = processed.replaceAllMapped(
      RegExp(r'<(https?://[^\s>]+)>'),
      (match) => match.group(1)!,
    );

    // 将裸 URL 转为 markdown 链接
    processed = processed.replaceAllMapped(_bareUrlRegex, (match) {
      final url = match.group(0)!;
      return '[$url]($url)';
    });

    // 还原代码块
    for (var i = 0; i < codeBlocks.length; i++) {
      processed = processed.replaceFirst('\x00CODE$i\x00', codeBlocks[i]);
    }

    return processed;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawContent = props['content'] as String? ?? '';
    final content = _autoLinkUrls(rawContent);
    return SelectionArea(
      child: GptMarkdown(
        content,
        style: Theme.of(context).textTheme.bodyMedium,
        useDollarSignsForLatex: true,
        codeBuilder: buildHighlightedCodeBlock,
        onLinkTap: (url, title) {
          debugPrint('[MarkdownWidget] onLinkTap fired: url=$url, title=$title');
          if (url.startsWith('http://') || url.startsWith('https://')) {
            // 外部链接 → 系统浏览器打开
            launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
          } else if (url.endsWith('.md')) {
            // .md 文件链接 → 请求 Server 读取文件内容
            final event = jsonEncode({
              'protocol': 'clawke_event_v1',
              'event_type': 'read_file',
              'data': {'filepath': url},
            });
            ref.read(wsServiceProvider).send(event);
          }
        },
      ),
    );
  }
}
