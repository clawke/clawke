import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/l10n/l10n.dart';

class ConversationListScreen extends ConsumerWidget {
  final void Function(String accountId)? onConversationTap;
  final bool showHeader;

  const ConversationListScreen({
    super.key,
    this.onConversationTap,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationListProvider);
    final selectedId = ref.watch(selectedAccountIdProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 顶部标题栏
        if (showHeader)
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? colorScheme.surfaceContainerLowest
                  : colorScheme.surfaceContainer,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.conversations,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        // 会话列表
        Expanded(
          child: conversationsAsync.when(
            data: (conversations) {
              if (conversations.isEmpty) {
                return Center(
                  child: Text(
                    context.l10n.noConversations,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conv = conversations[index];
                  return _ConversationTile(
                    conversation: conv,
                    isSelected: conv.accountId == selectedId,
                    onTap: () {
                      ref.read(selectedAccountIdProvider.notifier).state =
                          conv.accountId;
                      onConversationTap?.call(conv.accountId);
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(context.l10n.loadFailed(e.toString()))),
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(context, ref, details.globalPosition);
      },
      onLongPressStart: (details) {
        _showContextMenu(context, ref, details.globalPosition);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary.withOpacity(0.15) : null,
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          minVerticalPadding: 2,
          selected: isSelected,
          selectedTileColor: Colors.transparent,
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              (conversation.name ?? '?').characters.first,
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
          ),
          title: Row(
            children: [
              if (conversation.isPinned != 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.push_pin,
                    size: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              Expanded(
                flex: 2,
                child: Text(
                  conversation.name ?? conversation.accountId,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (conversation.lastMessageAt != null)
                Expanded(
                  flex: 1,
                  child: Text(
                    _formatTime(conversation.lastMessageAt!, l10n),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  conversation.lastMessagePreview ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              if (conversation.unseenCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: conversation.isMuted != 0
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    conversation.unseenCount > 99
                        ? '99+'
                        : '${conversation.unseenCount}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onError),
                  ),
                ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, Offset position) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 8),
              Text(l10n.renameConversation),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(
                Icons.cleaning_services_outlined,
                size: 18,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(l10n.clearConversation),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              Text(
                l10n.deleteConversation,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'rename':
          _showRename(context, ref);
        case 'clear':
          _confirmClear(context, ref);
        case 'delete':
          _confirmDelete(context, ref);
      }
    });
  }

  void _showRename(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(
      text: conversation.name ?? conversation.accountId,
    );
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameConversation),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (_) {
            final newName = controller.text.trim();
            if (newName.isNotEmpty) {
              ref
                  .read(conversationRepositoryProvider)
                  .renameConversation(conversation.accountId, newName);
              Navigator.of(ctx).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref
                    .read(conversationRepositoryProvider)
                    .renameConversation(conversation.accountId, newName);
                Navigator.of(ctx).pop();
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearConversation),
        content: Text(l10n.clearConversationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref
                  .read(messageRepositoryProvider)
                  .clearConversation(conversation.accountId);
            },
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConversation),
        content: Text(l10n.deleteConversationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final convId = conversation.accountId;
              // 如果当前选中的是这个会话，先取消选中
              if (ref.read(selectedAccountIdProvider) == convId) {
                ref.read(selectedAccountIdProvider.notifier).state = null;
              }
              // 先清空消息，再删除会话条目
              await ref
                  .read(messageRepositoryProvider)
                  .clearConversation(convId);
              await ref
                  .read(conversationRepositoryProvider)
                  .deleteConversation(convId);
            },
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int milliseconds, dynamic l10n) {
    final dt = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inHours < 1) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return l10n.daysAgo(diff.inDays);
    return '${dt.month}/${dt.day}';
  }
}
