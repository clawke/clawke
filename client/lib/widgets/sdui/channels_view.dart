import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

class ChannelsView extends ConsumerWidget {
  final Map<String, dynamic> props;
  final String messageId;

  const ChannelsView({super.key, required this.props, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final channels = props['channels'] as List<dynamic>? ?? [];
    final availableTypes = props['available_types'] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.hub, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '频道连接节点',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () {
                  ref.read(wsServiceProvider).sendJson({
                    'event_type': 'user_action',
                    'context': {'client_msg_id': messageId},
                    'action': {'action_id': 'refresh_channels', 'data': {}},
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (channels.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '无活跃连接',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: channels.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final channel = channels[index] as Map<String, dynamic>;
                return _ChannelCard(channel: channel, messageId: messageId);
              },
            ),
          const Divider(height: 32),
          Text('添加新连接:', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableTypes.map((typeObj) {
              final type = typeObj as Map<String, dynamic>;
              return ActionChip(
                avatar: const Icon(Icons.add_link, size: 16),
                label: Text(type['name'] ?? 'Unknown'),
                onPressed: () {
                  ref.read(wsServiceProvider).sendJson({
                    'event_type': 'user_action',
                    'context': {'client_msg_id': messageId},
                    'action': {
                      'action_id': 'get_channel_form',
                      'data': {'channel_type': type['id']},
                    },
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChannelCard extends ConsumerWidget {
  final Map<String, dynamic> channel;
  final String messageId;

  const _ChannelCard({required this.channel, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = channel['status'] as String? ?? 'disconnected';
    final isConnected = status == 'connected';
    final stats = channel['stats'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConnected
              ? Colors.green.withOpacity(0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel['name'] ?? 'Unknown Channel',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isConnected)
                TextButton(
                  child: const Text('断开', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    ref.read(wsServiceProvider).sendJson({
                      'event_type': 'user_action',
                      'context': {'client_msg_id': messageId},
                      'action': {
                        'action_id': 'disconnect_channel',
                        'data': {'channel_id': channel['id']},
                      },
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            channel['connection_string'] ?? '',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.message,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '消息收发: ${stats['messages'] ?? 0}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              if (stats['last_active'] != null) ...[
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '活跃: ${(stats['last_active'] as String).split('T').first}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
