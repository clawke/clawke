import 'package:flutter/material.dart';
import 'package:client/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:client/widgets/mermaid/widgets/mermaid_diagram.dart';
import 'package:client/widgets/mermaid/models/style.dart';
import 'package:client/widgets/mermaid/parser/mermaid_parser.dart';

/// 为 GptMarkdown 提供的代码块渲染器（带语法高亮 + Mermaid 图表 + Clarify/Approval 卡片）
///
/// 使用方法：在 GptMarkdown 中传入 `codeBuilder: buildHighlightedCodeBlock`
/// Mermaid 渲染需要通过 [setMermaidEnabled] 控制开关
/// Clarify/Approval 回复需要通过 [setClarifyResponseCallback] 设置回调
Widget buildHighlightedCodeBlock(
  BuildContext context,
  String language,
  String code,
  bool closed,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colorScheme = Theme.of(context).colorScheme;
  final lang = language.isNotEmpty ? language : 'plaintext';

  // ── Clarify 代码块：内联渲染为选择卡片 ──
  if (lang == 'clarify') {
    if (!closed) return _buildPendingCard(context, context.l10n.cardGeneratingOptions);
    final parsed = _parseClarifyContent(code);
    if (parsed != null) {
      return _InlineClarifyCard(
        cardKey: 'clarify:${code.hashCode}',
        rawCode: code,
        question: parsed.question,
        choices: parsed.choices,
        onRespond: _onClarifyResponse,
      );
    }
    // 解析失败 → fallback 到普通代码块
    return _buildCodeBlock(context, lang, code, isDark, colorScheme);
  }

  // ── Approval 代码块：内联渲染为审批卡片 ──
  if (lang == 'approval') {
    if (!closed) return _buildPendingCard(context, context.l10n.cardGeneratingApproval);
    final parsed = _parseApprovalContent(code);
    if (parsed != null) {
      return _InlineApprovalCard(
        cardKey: 'approval:${code.hashCode}',
        rawCode: code,
        command: parsed.command,
        description: parsed.description,
        risk: parsed.risk,
        onRespond: _onClarifyResponse,
      );
    }
    return _buildCodeBlock(context, lang, code, isDark, colorScheme);
  }

  // ── Approval 结果代码块：渲染为彩色引用块 ──
  if (lang == 'approval_result') {
    return _buildApprovalResultBlock(context, code);
  }

  // ── Clarify 结果代码块：渲染为彩色引用块 ──
  if (lang == 'clarify_result') {
    return _buildClarifyResultBlock(context, code);
  }

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

// ── Clarify/Approval 回调 ──────────────────────────
typedef ClarifyResponseCallback = void Function(String response);
typedef CardContentUpdateCallback = void Function(String codeBlock, String replacement);
ClarifyResponseCallback? _onClarifyResponse;
CardContentUpdateCallback? _onCardContentUpdate;

/// 外部调用设置 Clarify/Approval 回复回调（由 ChatScreen 设置）
void setClarifyResponseCallback(ClarifyResponseCallback? callback) {
  _onClarifyResponse = callback;
}

/// 外部调用设置卡片内容更新回调（响应后替换 DB 中的代码块为结果文本）
void setCardContentUpdateCallback(CardContentUpdateCallback? callback) {
  _onCardContentUpdate = callback;
}

/// 已响应卡片的内存缓存（key=卡片内容hash, value=用户选择）
/// 配合 DB 更新使用，作为立即生效的补充
final Map<String, String> _respondedCards = {};

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

// ── Clarify/Approval 内容解析 ──────────────────────

class _ClarifyParsed {
  final String question;
  final List<String> choices;
  _ClarifyParsed({required this.question, required this.choices});
}

class _ApprovalParsed {
  final String command;
  final String description;
  final String risk; // low | medium | high
  _ApprovalParsed({required this.command, required this.description, this.risk = 'medium'});
}

_ClarifyParsed? _parseClarifyContent(String content) {
  String question = '';
  final choices = <String>[];
  bool inChoices = false;
  for (final line in content.trim().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('question:')) {
      question = trimmed.substring('question:'.length).trim();
    } else if (trimmed == 'choices:') {
      inChoices = true;
    } else if (inChoices && trimmed.startsWith('- ')) {
      choices.add(trimmed.substring(2).trim());
    }
  }
  if (question.isEmpty) return null;
  return _ClarifyParsed(question: question, choices: choices);
}

_ApprovalParsed? _parseApprovalContent(String content) {
  String command = '', description = '', risk = 'medium';
  for (final line in content.trim().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('command:')) {
      command = trimmed.substring('command:'.length).trim();
    } else if (trimmed.startsWith('description:')) {
      description = trimmed.substring('description:'.length).trim();
    } else if (trimmed.startsWith('risk:')) {
      risk = trimmed.substring('risk:'.length).trim().toLowerCase();
    }
  }
  if (command.isEmpty) return null;
  return _ApprovalParsed(command: command, description: description.isNotEmpty ? description : command, risk: risk);
}

// ── 审批/澄清结果渲染（Style B 彩色引用块）──────────

Widget _buildApprovalResultBlock(BuildContext context, String code) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  String description = '', command = '', result = '';
  for (final line in code.trim().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('description:')) {
      description = trimmed.substring('description:'.length).trim();
    } else if (trimmed.startsWith('command:')) {
      command = trimmed.substring('command:'.length).trim();
    } else if (trimmed.startsWith('result:')) {
      result = trimmed.substring('result:'.length).trim().toLowerCase();
    }
  }

  final isApproved = result == 'approved';
  final borderColor = isApproved
      ? const Color(0xFF4ECCA3)
      : const Color(0xFFF85149);
  final statusIcon = isApproved ? '✅' : '🚫';
  final statusText = isApproved ? '已允许' : '已拒绝';

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: borderColor, width: 3)),
    ),
    padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              description,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (command.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                command,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        Text(
          '$statusIcon $statusText',
          style: textTheme.bodySmall?.copyWith(
            color: borderColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

Widget _buildClarifyResultBlock(BuildContext context, String code) {
  final colorScheme = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;

  String question = '', answer = '';
  for (final line in code.trim().split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('question:')) {
      question = trimmed.substring('question:'.length).trim();
    } else if (trimmed.startsWith('answer:')) {
      answer = trimmed.substring('answer:'.length).trim();
    }
  }

  const borderColor = Color(0xFF58A6FF);

  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: borderColor, width: 3)),
    ),
    padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (question.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              question,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (answer.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                answer,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        Text(
          '✅ 已选择',
          style: textTheme.bodySmall?.copyWith(
            color: const Color(0xFF4ECCA3),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ── 流式生成中的占位卡片 ──────────────────────────

Widget _buildPendingCard(BuildContext context, String hint) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(hint, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
      ],
    ),
  );
}

// ── 内联 Clarify 卡片 ──────────────────────────────

class _InlineClarifyCard extends StatefulWidget {
  final String cardKey;
  final String rawCode;
  final String question;
  final List<String> choices;
  final ClarifyResponseCallback? onRespond;

  const _InlineClarifyCard({
    required this.cardKey,
    required this.rawCode,
    required this.question,
    required this.choices,
    this.onRespond,
  });

  @override
  State<_InlineClarifyCard> createState() => _InlineClarifyCardState();
}

class _InlineClarifyCardState extends State<_InlineClarifyCard> {
  bool _responded = false;
  String? _selectedChoice;

  void _respond(String text) {
    if (_responded || text.trim().isEmpty) return;
    debugPrint('[InlineClarify] _respond: "$text", callback=${_onClarifyResponse != null}, contentUpdate=${_onCardContentUpdate != null}');
    setState(() { _responded = true; _selectedChoice = text; });
    _onClarifyResponse?.call(text);
    // 持久化：替换 DB 中的代码块为 clarify_result 标签
    _onCardContentUpdate?.call(
      '```clarify\n${widget.rawCode.trimRight()}\n```',
      '```clarify_result\nquestion: ${widget.question}\nanswer: $text\n```',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.secondary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.help_outline_rounded, size: 18, color: colorScheme.secondary),
            const SizedBox(width: 8),
            Text(context.l10n.cardNeedConfirm, style: textTheme.labelLarge?.copyWith(
              color: colorScheme.secondary, fontWeight: FontWeight.w600,
            )),
          ]),
          const SizedBox(height: 10),
          Text(widget.question, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
          const SizedBox(height: 12),
          if (_responded) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Flexible(child: Text(context.l10n.cardSelected(_selectedChoice ?? ''), style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary, fontWeight: FontWeight.w500,
                ))),
              ]),
            ),
          ] else if (widget.choices.isNotEmpty) ...[
            Wrap(
              spacing: 8, runSpacing: 6,
              children: widget.choices.map((choice) => Material(
                color: colorScheme.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _respond(choice),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text(choice, style: textTheme.labelMedium?.copyWith(
                        color: colorScheme.secondary, fontWeight: FontWeight.w500,
                      )),
                    ]),
                  ),
                ),
              )).toList(),
            ),
            const SizedBox(height: 8),
            Text(context.l10n.cardOtherOptionHint,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 内联 Approval 卡片 ──────────────────────────────

class _InlineApprovalCard extends StatefulWidget {
  final String cardKey;
  final String rawCode;
  final String command;
  final String description;
  final String risk;
  final ClarifyResponseCallback? onRespond;

  const _InlineApprovalCard({
    required this.cardKey,
    required this.rawCode,
    required this.command,
    required this.description,
    this.risk = 'medium',
    this.onRespond,
  });

  @override
  State<_InlineApprovalCard> createState() => _InlineApprovalCardState();
}

class _InlineApprovalCardState extends State<_InlineApprovalCard> {
  bool _responded = false;
  String? _choice;

  void _respond(String choice) {
    if (_responded) return;
    debugPrint('[InlineApproval] _respond: "$choice", callback=${_onClarifyResponse != null}, contentUpdate=${_onCardContentUpdate != null}');
    setState(() { _responded = true; _choice = choice; });
    _onClarifyResponse?.call(choice == 'deny' ? 'n' : 'y');
    // 持久化：替换 DB 中的代码块为 approval_result 标签
    final result = choice == 'deny' ? 'denied' : 'approved';
    _onCardContentUpdate?.call(
      '```approval\n${widget.rawCode.trimRight()}\n```',
      '```approval_result\ndescription: ${widget.description}\ncommand: ${widget.command}\nresult: $result\n```',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.tertiary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: colorScheme.tertiary),
            const SizedBox(width: 8),
            Text(context.l10n.cardNeedConfirm, style: textTheme.labelLarge?.copyWith(
              color: colorScheme.tertiary, fontWeight: FontWeight.w600,
            )),
            const Spacer(),
            _buildRiskBadge(context, widget.risk),
          ]),
          const SizedBox(height: 10),
          Text(widget.description, style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface)),
          if (widget.command.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.command, style: textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace', color: colorScheme.onSurface,
              ), maxLines: 5, overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 12),
          if (_responded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_choice == 'deny' ? colorScheme.error : colorScheme.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(_choice == 'deny' ? Icons.block : Icons.check_circle,
                  size: 16, color: _choice == 'deny' ? colorScheme.error : colorScheme.primary),
                const SizedBox(width: 8),
                Text(_choice == 'deny' ? context.l10n.cardDenied : context.l10n.cardApproved, style: textTheme.bodySmall?.copyWith(
                  color: _choice == 'deny' ? colorScheme.error : colorScheme.primary,
                  fontWeight: FontWeight.w500,
                )),
              ]),
            )
          else
            Wrap(spacing: 8, runSpacing: 6, children: [
              _buildAction(context, context.l10n.cardApprove, Icons.check_rounded, colorScheme.primary, () => _respond('once')),
              _buildAction(context, context.l10n.cardDeny, Icons.close_rounded, colorScheme.error, () => _respond('deny')),
            ]),
        ],
      ),
    );
  }

  Widget _buildAction(BuildContext context, String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color, fontWeight: FontWeight.w500,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildRiskBadge(BuildContext context, String risk) {
    final l10n = context.l10n;
    final (label, color) = switch (risk) {
      'high' => (l10n.cardRiskHigh, Colors.red),
      'low' => (l10n.cardRiskLow, Colors.green),
      _ => (l10n.cardRiskMedium, Colors.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color, fontWeight: FontWeight.w600, fontSize: 11,
      )),
    );
  }
}
