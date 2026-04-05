import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/debug_log_provider.dart';
import 'package:client/l10n/l10n.dart';

/// 底部调试日志面板，显示 WebSocket 和 CUP 协议日志
class DebugLogPanel extends ConsumerStatefulWidget {
  const DebugLogPanel({super.key});

  @override
  ConsumerState<DebugLogPanel> createState() => _DebugLogPanelState();
}

class _DebugLogPanelState extends ConsumerState<DebugLogPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(debugLogMessagesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // 日志变化时自动滚动到底部
    ref.listen(debugLogMessagesProvider, (_, __) => _scrollToBottom());

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: colorScheme.brightness == Brightness.dark
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // 标题栏
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.06),
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'DEBUG LOG',
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                    letterSpacing: 0.8,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
                const Spacer(),
                // 清除按钮
                _PanelButton(
                  icon: Icons.delete_outline,
                  tooltip: context.l10n.clearLogs,
                  onTap: () =>
                      ref.read(debugLogMessagesProvider.notifier).clearLogs(),
                ),
                const SizedBox(width: 4),
                // 关闭按钮
                _PanelButton(
                  icon: Icons.close,
                  tooltip: context.l10n.closeLogPanel,
                  onTap: () =>
                      ref.read(debugLogEnabledProvider.notifier).setEnabled(false),
                ),
              ],
            ),
          ),
          // 日志内容
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Text(
                      context.l10n.noLogs,
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return Text(
                          logs[index],
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                            height: 1.6,
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'JetBrains Mono',
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _PanelButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
