import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/screens/conversation_settings_sheet.dart';

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
    final selectedId = ref.watch(selectedConversationIdProvider);
    final colorScheme = Theme.of(context).colorScheme;


    final headerBg = Theme.of(context).brightness == Brightness.dark
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainer;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: showHeader
          ? AppBar(
              automaticallyImplyLeading: false,
              centerTitle: false,
              title: Text(context.l10n.conversations),
              backgroundColor: headerBg,
              surfaceTintColor: Colors.transparent,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  color: colorScheme.outlineVariant.withOpacity(0.5),
                ),
              ),
              actions: [
                NewConversationButton(
                  onCreated: (convId) {
                    ref.read(selectedConversationIdProvider.notifier).state = convId;
                    onConversationTap?.call(convId);
                  },
                ),
              ],
            )
          : null,
      body: conversationsAsync.when(
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
              return Dismissible(
                key: Key(conv.conversationId),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return await _showDeleteConfirm(context, ref, conv);
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: colorScheme.error,
                  child: Icon(
                    Icons.delete_outline,
                    color: colorScheme.onError,
                  ),
                ),
                child: _ConversationTile(
                  conversation: conv,
                  isSelected: conv.conversationId == selectedId,
                  onTap: () {
                    ref.read(selectedConversationIdProvider.notifier).state =
                        conv.conversationId;
                    onConversationTap?.call(conv.conversationId);
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(context.l10n.loadFailed(e.toString()))),
      ),
    );
  }

  /// 滑动删除确认弹窗（返回 true 表示确认删除）
  Future<bool> _showDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    Conversation conv,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConversation),
        content: Text(l10n.deleteConversationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final convId = conv.conversationId;
      if (ref.read(selectedConversationIdProvider) == convId) {
        ref.read(selectedConversationIdProvider.notifier).state = null;
      }
      await ref
          .read(conversationRepositoryProvider)
          .deleteConversation(convId);
      await ref
          .read(messageRepositoryProvider)
          .clearConversation(convId);
      return true;
    }
    return false;
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
                  .renameConversation(conversation.conversationId, newName);
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
                    .renameConversation(conversation.conversationId, newName);
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
                  .clearConversation(conversation.conversationId);
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
              final convId = conversation.conversationId;
              // 如果当前选中的是这个会话，先取消选中
              if (ref.read(selectedConversationIdProvider) == convId) {
                ref.read(selectedConversationIdProvider.notifier).state = null;
              }
              // 先删除会话条目（避免 clearConversation 更新 lastMessageAt 导致列表抖动）
              await ref
                  .read(conversationRepositoryProvider)
                  .deleteConversation(convId);
              // 再清消息（会话条目已删，不会触发列表重排）
              await ref
                  .read(messageRepositoryProvider)
                  .clearConversation(convId);
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

  void _showSettings(BuildContext context) {
    ConversationSettingsSheet.show(
      context,
      conversationId: conversation.conversationId,
      accountId: conversation.accountId,
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

/// "+" 按钮：新建会话
class NewConversationButton extends ConsumerWidget {
  final void Function(String conversationId)? onCreated;
  final double iconSize;

  const NewConversationButton({super.key, this.onCreated, this.iconSize = 22});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(connectedAccountsProvider);
    final minDim = iconSize + 14;
    // 没有在线后端时也显示按钮（但禁用）
    return IconButton(
      icon: Icon(Icons.add, size: iconSize),
      tooltip: context.l10n.newConversation,
      onPressed: accounts.isEmpty ? null : () => _onTap(context, ref, accounts),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: minDim, minHeight: minDim),
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    List<ConnectedAccount> accounts,
  ) async {
    String accountId;

    if (accounts.length == 1) {
      // 单后端：直接创建
      accountId = accounts.first.accountId;
    } else {
      // 多后端：弹出选择器
      final selected = await showDialog<ConnectedAccount>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          final tt = Theme.of(ctx).textTheme;
          return AlertDialog(
            title: Text(context.l10n.newConversation),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.selectAIBackend,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ...accounts.map((a) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: cs.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(ctx).pop(a),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.smart_toy_outlined,
                                  color: cs.primary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  a.accountId,
                                  style: tt.titleSmall,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: cs.onSurfaceVariant.withOpacity(0.4),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          );
        },
      );
      if (selected == null) return; // 取消
      accountId = selected.accountId;
    }

    // 打开创建模式设置面板（点创建才生成 ID，取消则不创建）
    if (context.mounted) {
      ConversationSettingsSheet.showCreate(
        context,
        accountId: accountId,
        onCreated: (id) => onCreated?.call(id),
      );
    }
  }
}
