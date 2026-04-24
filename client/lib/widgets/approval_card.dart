import 'package:flutter/material.dart';
import 'package:client/providers/approval_provider.dart';

/// 审批请求卡片 — AI 请求用户确认执行某个操作
///
/// 显示命令描述 + 四个选项按钮（允许一次 / 允许本次会话 / 始终允许 / 拒绝）
class ApprovalCard extends StatefulWidget {
  final ApprovalRequest request;
  final void Function(String choice) onRespond;

  const ApprovalCard({
    super.key,
    required this.request,
    required this.onRespond,
  });

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _responded = false;
  String? _choice;

  void _respond(String choice) {
    if (_responded) return;
    setState(() { _responded = true; _choice = choice; });
    widget.onRespond(choice);
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
        border: Border.all(
          color: colorScheme.tertiary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 18,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                '需要确认',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Command description
          if (widget.request.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.request.description,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),

          // Command (monospace)
          if (widget.request.command.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.request.command,
                style: textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['.AppleSystemUIFont', 'Roboto Mono'],
                  color: colorScheme.onSurface,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // 已响应 → 显示结果状态
          if (_responded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_choice == 'deny' ? colorScheme.error : colorScheme.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_choice == 'deny' ? Icons.block : Icons.check_circle,
                    size: 16, color: _choice == 'deny' ? colorScheme.error : colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(_choice == 'deny' ? '已拒绝' : '已允许',
                    style: textTheme.bodySmall?.copyWith(
                      color: _choice == 'deny' ? colorScheme.error : colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    )),
                ],
              ),
            )
          else
            // Action buttons
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ActionButton(
                  label: '允许',
                  icon: Icons.check_rounded,
                  color: colorScheme.primary,
                  onTap: () => _respond('once'),
                ),
                _ActionButton(
                  label: '本次会话',
                  icon: Icons.check_circle_outline,
                  color: colorScheme.primary.withOpacity(0.8),
                  onTap: () => _respond('session'),
                ),
                _ActionButton(
                  label: '始终允许',
                  icon: Icons.verified_outlined,
                  color: colorScheme.tertiary,
                  onTap: () => _respond('always'),
                ),
                _ActionButton(
                  label: '拒绝',
                  icon: Icons.close_rounded,
                  color: colorScheme.error,
                  onTap: () => _respond('deny'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 澄清请求卡片 — AI 需要用户提供更多信息
///
/// 显示问题文本 + 选项按钮（如有）+ 自由输入框
class ClarifyCard extends StatefulWidget {
  final ClarifyRequest request;
  final void Function(String response) onRespond;

  const ClarifyCard({
    super.key,
    required this.request,
    required this.onRespond,
  });

  @override
  State<ClarifyCard> createState() => _ClarifyCardState();
}

class _ClarifyCardState extends State<ClarifyCard> {
  final _controller = TextEditingController();
  bool _responded = false;
  String? _responseText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !_responded) {
      setState(() { _responded = true; _responseText = text; });
      widget.onRespond(text);
    }
  }

  void _respondChoice(String choice) {
    if (_responded) return;
    setState(() { _responded = true; _responseText = choice; });
    widget.onRespond(choice);
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
        border: Border.all(
          color: colorScheme.secondary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                '需要确认',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Question
          Text(
            widget.request.question,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // 已响应 → 显示回答
          if (_responded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('已回答: $_responseText',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Choice buttons (if provided)
            if (widget.request.choices.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.request.choices.map((choice) {
                  return _ActionButton(
                    label: choice,
                    icon: Icons.arrow_forward_ios_rounded,
                    color: colorScheme.secondary,
                    onTap: () => _respondChoice(choice),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Text(
                '或输入自由回答：',
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
            ],

            // Free text input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '输入回答...',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colorScheme.outline.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: colorScheme.secondary,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: colorScheme.onSecondary,
                    minimumSize: const Size(36, 36),
                  ),
                  onPressed: _submit,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 共用的迷你 Action 按钮
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
