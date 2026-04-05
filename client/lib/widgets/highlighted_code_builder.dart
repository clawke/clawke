import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:client/widgets/mermaid/widgets/mermaid_diagram.dart';
import 'package:client/widgets/mermaid/models/style.dart';
import 'package:client/widgets/mermaid/parser/mermaid_parser.dart';

/// 为 GptMarkdown 提供的代码块渲染器（带语法高亮 + Mermaid 图表支持）
///
/// 使用方法：在 GptMarkdown 中传入 `codeBuilder: buildHighlightedCodeBlock`
/// Mermaid 渲染需要通过 [setMermaidEnabled] 控制开关
Widget buildHighlightedCodeBlock(
  BuildContext context,
  String language,
  String code,
  bool closed,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colorScheme = Theme.of(context).colorScheme;
  final lang = language.isNotEmpty ? language : 'plaintext';

  // Mermaid 图表渲染（先验证能否解析，失败则 fallback 到代码块）
  if (_mermaidEnabled && _isMermaidLanguage(lang) && closed) {
    if (_canParseMermaid(code)) {
      return _buildMermaidBlock(context, code, isDark, colorScheme);
    }
    // 解析失败 → 显示原始代码
    return _buildCodeBlock(context, 'mermaid', code, isDark, colorScheme);
  }

  // 普通代码高亮
  return _buildCodeBlock(context, lang, code, isDark, colorScheme);
}

// ── Mermaid 开关 ──────────────────────────────────
bool _mermaidEnabled = true;

/// 外部调用设置 Mermaid 渲染开关
void setMermaidEnabled(bool enabled) {
  _mermaidEnabled = enabled;
}

bool _isMermaidLanguage(String lang) {
  final lower = lang.toLowerCase().trim();
  return lower == 'mermaid' || lower.startsWith('mermaid');
}

bool _canParseMermaid(String code) {
  try {
    final result = const MermaidParser().parseWithData(code);
    return result != null;
  } catch (_) {
    return false;
  }
}

// ── Mermaid 渲染 ──────────────────────────────────
Widget _buildMermaidBlock(
  BuildContext context,
  String code,
  bool isDark,
  ColorScheme colorScheme,
) {
  final mermaidStyle = isDark ? MermaidStyle.dark() : MermaidStyle.neutral();

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.schema_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Mermaid',
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // 全屏查看按钮
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () =>
                    _openMermaidFullscreen(context, code, mermaidStyle),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Icon(
                    Icons.fullscreen,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 复制代码按钮
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '复制代码',
                        style: TextStyle(
                          fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 图表区域（水平可滚动）
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Color(mermaidStyle.backgroundColor),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: MermaidDiagram(code: code, style: mermaidStyle),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 全屏查看 Mermaid 图表（支持缩放和拖拽）
void _openMermaidFullscreen(
  BuildContext context,
  String code,
  MermaidStyle style,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.9,
        height: MediaQuery.of(ctx).size.height * 0.85,
        child: Column(
          children: [
            // 顶部栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schema_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Mermaid — 缩放和拖拽查看',
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    tooltip: '关闭',
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            // InteractiveViewer 区域
            Expanded(
              child: InteractiveMermaidDiagram(
                code: code,
                style: style,
                minScale: 0.3,
                maxScale: 4.0,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── 普通代码高亮 ──────────────────────────────────
Widget _buildCodeBlock(
  BuildContext context,
  String lang,
  String code,
  bool isDark,
  ColorScheme colorScheme,
) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部栏：语言标签 + 复制按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              Text(
                lang,
                style: TextStyle(
                  fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                  color: colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '复制代码',
                        style: TextStyle(
                          fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 代码内容区
        ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          child: HighlightView(
            code,
            language: lang,
            theme: isDark ? monokaiSublimeTheme : githubTheme,
            padding: const EdgeInsets.all(12),
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
