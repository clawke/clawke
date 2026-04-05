import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/reply_provider.dart';
import 'package:client/l10n/l10n.dart';

class MessageContextMenu extends ConsumerWidget {
  final Message message;
  final bool isUser;
  final Widget child;

  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isUser,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Platform.isIOS || Platform.isAndroid;
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showMenu(context, ref, details.globalPosition);
      },
      // 仅移动端注册长按菜单；桌面端由 SelectionArea 处理长按选中文字
      onLongPressStart: isMobile
          ? (details) { _showMenu(context, ref, details.globalPosition); }
          : null,
      child: child,
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref, Offset position) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = context.l10n;

    final items = <PopupMenuEntry<String>>[
      // 回复
      PopupMenuItem(
        value: 'reply',
        child: Row(
          children: [
            const Icon(Icons.reply, size: 18),
            const SizedBox(width: 8),
            Text(t.reply),
          ],
        ),
      ),
      // 复制
      if (message.content != null && message.content!.isNotEmpty)
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18),
              const SizedBox(width: 8),
              Text(t.copy),
            ],
          ),
        ),
      // 编辑 (仅自己的文本消息)
      if (isUser && message.type == 'text')
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 18),
              const SizedBox(width: 8),
              Text(t.edit),
            ],
          ),
        ),
      // 删除 (仅自己的消息)
      if (isUser)
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              Text(t.delete, style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      // 重试 (仅失败消息)
      if (message.status == 'failed')
        PopupMenuItem(
          value: 'retry',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 18),
              const SizedBox(width: 8),
              Text(t.retry),
            ],
          ),
        ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'reply':
          ref.read(replyingToProvider.notifier).state = message;
        case 'copy':
          Clipboard.setData(ClipboardData(text: message.content ?? ''));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t.copied),
                duration: const Duration(seconds: 1),
              ),
            );
          }
        case 'edit':
          ref.read(editingMessageProvider.notifier).state = message;
        case 'delete':
          _confirmDelete(context, ref);
        case 'retry':
          ref.read(messageRepositoryProvider).retryMessage(message.messageId);
      }
    });
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = context.l10n;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteMessage),
        content: Text(t.deleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(messageRepositoryProvider)
                  .deleteMessage(message.messageId);
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(t.delete),
          ),
        ],
      ),
    );
  }
}
