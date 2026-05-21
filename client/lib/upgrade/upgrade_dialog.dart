import 'package:flutter/material.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/widgets/markdown_widget.dart';
import 'upgrade_model.dart';
import 'platform_installer.dart';

/// 统一升级弹窗
///
/// - upgrade=1: 可选升级，显示「知道了」和「立即更新」
/// - upgrade=2: 强制升级，只显示「立即更新」，不可关闭
class UpgradeDialog extends StatelessWidget {
  final UpgradeInfo info;
  final Future<void> Function()? onRetry;

  const UpgradeDialog({super.key, required this.info, this.onRetry});

  /// 显示升级弹窗
  static Future<void> show(
    BuildContext context,
    UpgradeInfo info, {
    Future<void> Function()? onRetry,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !info.isForced,
      builder: (ctx) => UpgradeDialog(info: info, onRetry: onRetry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final title = info.title.isNotEmpty ? info.title : '发现新版本 v${info.version}';
    final isServerUpdate = info.action.endsWith('_server_update');
    final primaryLabel = isServerUpdate ? '重新检查' : '立即更新';
    return PopScope(
      canPop: !info.isForced,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: Colors.cyanAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(info.message, style: theme.textTheme.bodyMedium),
                ),
              if (info.releaseDate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '发布日期：${info.releaseDate}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              // Changelog — Markdown 渲染
              if (info.changelog.isNotEmpty && info.message.isEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: MarkdownWidget(
                      props: {'content': info.changelog},
                      actions: const [],
                      messageId: 'upgrade_dialog',
                    ),
                  ),
                ),
              if (info.isForced)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '此版本为强制更新',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          // 「知道了」仅在可选升级时显示 — Show acknowledgement only for optional updates.
          if (!info.isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(textStyle: theme.textTheme.bodySmall),
              child: Text(l10n.upgradeAcknowledge),
            ),
          // 「立即更新」
          FilledButton.icon(
            onPressed: () async {
              if (isServerUpdate) {
                await onRetry?.call();
                return;
              }
              await PlatformInstaller.install(info);
              if (context.mounted && !info.isForced) {
                Navigator.of(context).pop();
              }
            },
            icon: Icon(
              isServerUpdate ? Icons.refresh : Icons.download,
              size: 18,
            ),
            label: Text(primaryLabel),
          ),
        ],
      ),
    );
  }
}
