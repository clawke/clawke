import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

class CronListView extends ConsumerWidget {
  final Map<String, dynamic> props;
  final String messageId;

  const CronListView({super.key, required this.props, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = props['stats'] as Map<String, dynamic>? ?? {};
    final jobs = props['jobs'] as List<dynamic>? ?? [];

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
              Icon(Icons.schedule, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '定时任务 (${stats['active']}/${stats['total']})',
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
                    'action': {'action_id': 'refresh_cron', 'data': {}},
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (jobs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '暂无定时任务',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: jobs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final job = jobs[index] as Map<String, dynamic>;
                return _CronJobCard(job: job, messageId: messageId);
              },
            ),
        ],
      ),
    );
  }
}

class _CronJobCard extends ConsumerWidget {
  final Map<String, dynamic> job;
  final String messageId;

  const _CronJobCard({required this.job, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enabled = job['enabled'] == true;
    final lastRun = job['last_run'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled
              ? theme.colorScheme.primary.withOpacity(0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job['name'] ?? 'Unnamed Job',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (val) {
                  ref.read(wsServiceProvider).sendJson({
                    'event_type': 'user_action',
                    'context': {'client_msg_id': messageId},
                    'action': {
                      'action_id': 'toggle_cron_job',
                      'data': {'job_id': job['id'], 'enabled': val},
                    },
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                job['schedule_text'] ?? job['schedule'] ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 16),
              if (lastRun != null) ...[
                Icon(
                  lastRun['success'] == true ? Icons.check_circle : Icons.error,
                  size: 14,
                  color: lastRun['success'] == true ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '最后执行: ${lastRun['time']?.split('T').first ?? ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            job['message'] ?? '',
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('立即执行'),
              onPressed: () {
                ref.read(wsServiceProvider).sendJson({
                  'event_type': 'user_action',
                  'context': {'client_msg_id': messageId},
                  'action': {
                    'action_id': 'trigger_cron_job',
                    'data': {'job_id': job['id']},
                  },
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
