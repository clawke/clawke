import 'package:flutter/material.dart';

/// 可折叠的 Thinking 块组件
/// 参考 ClawX 的 ThinkingBlock 实现，用 Flutter 原生重写
class ThinkingBlockWidget extends StatefulWidget {
  final String content;
  final bool isStreaming;

  const ThinkingBlockWidget({
    super.key,
    required this.content,
    this.isStreaming = false,
  });

  @override
  State<ThinkingBlockWidget> createState() => _ThinkingBlockWidgetState();
}

class _ThinkingBlockWidgetState extends State<ThinkingBlockWidget>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _iconController;

  @override
  void initState() {
    super.initState();
    _iconController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    // 流式阶段默认展开
    if (widget.isStreaming) {
      _expanded = true;
      _iconController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(ThinkingBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 流式结束（收到正式消息）→ 自动收起
    if (oldWidget.isStreaming && !widget.isStreaming) {
      setState(() {
        _expanded = false;
        _iconController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _iconController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _iconController.forward();
      } else {
        _iconController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：点击展开/折叠
          InkWell(
            onTap: _toggle,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.25).animate(
                      CurvedAnimation(
                        parent: _iconController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.psychology,
                    size: 16,
                    color: colorScheme.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isStreaming ? 'Thinking...' : 'Thinking',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (widget.isStreaming) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colorScheme.primary.withOpacity(0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // 展开区域：纯文本渲染（thinking 内容是模型内部推理，不含 Markdown）
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: SelectableText(
                widget.content,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.75),
                  height: 1.5,
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
