import 'package:client/l10n/l10n.dart';
import 'package:flutter/material.dart';

class MobileManagementScreen extends StatelessWidget {
  final VoidCallback onDashboardTap;
  final VoidCallback onTasksTap;
  final VoidCallback onSkillsTap;
  final VoidCallback onSkillHubTap;

  const MobileManagementScreen({
    super.key,
    required this.onDashboardTap,
    required this.onTasksTap,
    required this.onSkillsTap,
    required this.onSkillHubTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(l10n.navManagement),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ManagementSection(
            title: l10n.managementWorkspaceTitle,
            subtitle: l10n.managementWorkspaceSubtitle,
            children: [
              _ManagementTile(
                key: const ValueKey('mobile_management_dashboard'),
                icon: Icons.dashboard_outlined,
                iconColor: const Color(0xFF60A5FA),
                title: l10n.navDashboard,
                subtitle: l10n.managementDashboardSubtitle,
                onTap: onDashboardTap,
              ),
              const SizedBox(height: 10),
              _ManagementTile(
                key: const ValueKey('mobile_management_tasks'),
                icon: Icons.task_alt_outlined,
                iconColor: const Color(0xFF34D399),
                title: l10n.navTasks,
                subtitle: l10n.managementTasksSubtitle,
                onTap: onTasksTap,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _ManagementSection(
            title: l10n.managementCapabilitiesTitle,
            subtitle: l10n.managementCapabilitiesSubtitle,
            children: [
              _ManagementTile(
                key: const ValueKey('mobile_management_skills'),
                icon: Icons.settings_suggest_outlined,
                iconColor: const Color(0xFFA78BFA),
                title: l10n.navSkills,
                subtitle: l10n.managementSkillsSubtitle,
                onTap: onSkillsTap,
              ),
              const SizedBox(height: 10),
              _ManagementTile(
                key: const ValueKey('mobile_management_skillhub'),
                icon: Icons.extension_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: l10n.navSkillHub,
                subtitle: l10n.managementSkillHubSubtitle,
                onTap: onSkillHubTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManagementSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ManagementSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _ManagementTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManagementTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
