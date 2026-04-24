import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/ws_state_provider.dart';

class SkillsView extends ConsumerWidget {
  final Map<String, dynamic> props;
  final String messageId;

  const SkillsView({super.key, required this.props, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeTab = props['active_tab'] as String? ?? 'local';
    final localSkills = props['local_skills'] as List<dynamic>? ?? [];
    final marketSkills = props['market_skills'] as List<dynamic>? ?? [];

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
              Icon(Icons.extension, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '技能中心',
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
                    'action': {
                      'action_id': 'refresh_skills',
                      'data': {'tab': activeTab},
                    },
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 自定义 Tab
          Row(
            children: [
              Expanded(
                child: _TabButton(
                  title: '已安装',
                  isActive: activeTab == 'local',
                  onTap: () {
                    if (activeTab != 'local') {
                      ref.read(wsServiceProvider).sendJson({
                        'event_type': 'user_action',
                        'context': {'client_msg_id': messageId},
                        'action': {
                          'action_id': 'refresh_skills',
                          'data': {'tab': 'local'},
                        },
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TabButton(
                  title: '市场 ($activeTab)',
                  isActive: activeTab == 'market',
                  onTap: () {
                    if (activeTab != 'market') {
                      ref.read(wsServiceProvider).sendJson({
                        'event_type': 'user_action',
                        'context': {'client_msg_id': messageId},
                        'action': {
                          'action_id': 'refresh_skills',
                          'data': {'tab': 'market'},
                        },
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (activeTab == 'local')
            _buildLocalSkillsList(localSkills, theme)
          else
            _buildMarketSkillsList(marketSkills, theme),
        ],
      ),
    );
  }

  Widget _buildLocalSkillsList(List<dynamic> skills, ThemeData theme) {
    if (skills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            '尚未安装任何技能',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: skills.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final skill = skills[index] as Map<String, dynamic>;
        return _LocalSkillCard(skill: skill, messageId: messageId);
      },
    );
  }

  Widget _buildMarketSkillsList(List<dynamic> skills, ThemeData theme) {
    if (skills.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Text(
            '市场暂无可用技能',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: skills.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final skill = skills[index] as Map<String, dynamic>;
        return _MarketSkillCard(skill: skill, messageId: messageId);
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: isActive
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _LocalSkillCard extends ConsumerWidget {
  final Map<String, dynamic> skill;
  final String messageId;

  const _LocalSkillCard({required this.skill, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isActive = skill['status'] == 'active';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive
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
                  skill['name'] ?? 'Unknown',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Switch(
                value: isActive,
                onChanged: (val) {
                  ref.read(wsServiceProvider).sendJson({
                    'event_type': 'user_action',
                    'context': {'client_msg_id': messageId},
                    'action': {
                      'action_id': 'toggle_skill',
                      'data': {'skill_id': skill['id'], 'active': val},
                    },
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Version: ${skill['version'] ?? 'x.x'} • 作者: ${skill['author'] ?? 'Unknown'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(skill['description'] ?? '', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  ref.read(wsServiceProvider).sendJson({
                    'event_type': 'user_action',
                    'context': {'client_msg_id': messageId},
                    'action': {
                      'action_id': 'uninstall_skill',
                      'data': {'skill_id': skill['id']},
                    },
                  });
                },
                child: const Text('卸载', style: TextStyle(color: Colors.red)),
              ),
              if (skill['has_config'] == true) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('配置'),
                  onPressed: () {
                    ref.read(wsServiceProvider).sendJson({
                      'event_type': 'user_action',
                      'context': {'client_msg_id': messageId},
                      'action': {
                        'action_id': 'get_skill_config',
                        'data': {'skill_id': skill['id']},
                      },
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MarketSkillCard extends ConsumerWidget {
  final Map<String, dynamic> skill;
  final String messageId;

  const _MarketSkillCard({required this.skill, required this.messageId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isInstalled = skill['installed'] == true;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  skill['name'] ?? 'Unknown',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isInstalled)
                Chip(
                  label: Text('已安装', style: TextStyle(fontSize: Theme.of(context).textTheme.labelSmall!.fontSize)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('安装'),
                  onPressed: () {
                    ref.read(wsServiceProvider).sendJson({
                      'event_type': 'user_action',
                      'context': {'client_msg_id': messageId},
                      'action': {
                        'action_id': 'install_skill',
                        'data': {'skill_id': skill['id']},
                      },
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${skill['downloads'] ?? 0} 次下载 • 作者: ${skill['author'] ?? 'Unknown'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(skill['description'] ?? '', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
