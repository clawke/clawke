import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/skills_provider.dart';

enum _SkillStatusFilter { all, enabled, disabled }

enum _SkillSourceFilter { all, managed, external, readonly }

class SkillsManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const SkillsManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<SkillsManagementScreen> createState() =>
      _SkillsManagementScreenState();
}

class _SkillsManagementScreenState
    extends ConsumerState<SkillsManagementScreen> {
  final _searchController = TextEditingController();
  _SkillStatusFilter _statusFilter = _SkillStatusFilter.all;
  _SkillSourceFilter _sourceFilter = _SkillSourceFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(skillsControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SkillsState>(skillsControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null && message != previous?.errorMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    });

    final state = ref.watch(skillsControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final list = RefreshIndicator(
            onRefresh: () =>
                ref.read(skillsControllerProvider.notifier).refresh(),
            child: _buildSkillsList(state, compact: !wide),
          );

          if (!wide) return list;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScopeSidebar(
                scopes: state.scopes,
                selectedScopeId: state.selectedScopeId,
                isLoading: state.isLoading,
                onSelected: _selectScope,
              ),
              Expanded(child: list),
            ],
          );
        },
      ),
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.navSkills),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: content,
    );
  }

  List<ManagedSkill> _filtered(List<ManagedSkill> skills) {
    final query = _searchController.text.trim().toLowerCase();
    return skills.where((skill) {
      final matchesStatus = switch (_statusFilter) {
        _SkillStatusFilter.all => true,
        _SkillStatusFilter.enabled => skill.enabled,
        _SkillStatusFilter.disabled => !skill.enabled,
      };
      if (!matchesStatus) return false;
      final matchesSource = switch (_sourceFilter) {
        _SkillSourceFilter.all => true,
        _SkillSourceFilter.managed => skill.source == 'managed',
        _SkillSourceFilter.external => skill.source == 'external',
        _SkillSourceFilter.readonly => skill.source == 'readonly',
      };
      if (!matchesSource) return false;
      if (query.isEmpty) return true;
      return skill.name.toLowerCase().contains(query) ||
          skill.description.toLowerCase().contains(query) ||
          skill.category.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildSkillsList(SkillsState state, {required bool compact}) {
    final filteredSkills = _filtered(state.skills);
    final showLoadingPanel = state.isLoading && state.skills.isEmpty;
    final showEmptyPanel = !showLoadingPanel && filteredSkills.isEmpty;
    final hasMobileScopeSelector = compact && state.scopes.isNotEmpty;
    final leadingCount = hasMobileScopeSelector ? 6 : 4;
    final itemCount = showLoadingPanel || showEmptyPanel
        ? leadingCount + 1
        : filteredSkills.length + leadingCount;

    return ListView.builder(
      padding: EdgeInsets.all(compact ? 16 : 28),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasMobileScopeSelector) {
          if (index == 0) {
            return _MobileScopeSelector(
              scope: state.selectedScope,
              isReadOnly: state.isScopeReadOnly,
              onTap: _showScopeSheet,
            );
          }
          if (index == 1) return const SizedBox(height: 18);
          index -= 2;
        }

        if (index == 0) {
          return _Header(
            total: state.skills.length,
            enabled: state.skills.where((skill) => skill.enabled).length,
            isLoading: state.isLoading,
            isReadOnly: state.isScopeReadOnly,
            onCreate: () => _openEditor(),
            onRefresh: () =>
                ref.read(skillsControllerProvider.notifier).refresh(),
          );
        }
        if (index == 1 || index == 3) return const SizedBox(height: 18);
        if (index == 2) {
          return _Toolbar(
            controller: _searchController,
            filter: _statusFilter,
            sourceFilter: _sourceFilter,
            onFilterChanged: (filter) => setState(() => _statusFilter = filter),
            onSourceFilterChanged: (filter) =>
                setState(() => _sourceFilter = filter),
            onChanged: (_) => setState(() {}),
          );
        }
        if (showLoadingPanel) return const _LoadingPanel();
        if (showEmptyPanel) return const _EmptyPanel();

        final skill = filteredSkills[index - 4];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _SkillCard(
            skill: skill,
            isBusy: state.busySkillIds.contains(skill.id),
            isToggleBusy: state.togglingSkillIds.contains(skill.id),
            readOnlyScope: state.isScopeReadOnly,
            onToggle: _toggleSkill,
            onEdit: _editSkill,
            onDelete: _deleteSkill,
          ),
        );
      },
    );
  }

  Future<void> _selectScope(String scopeId) async {
    await ref.read(skillsControllerProvider.notifier).selectScope(scopeId);
  }

  Future<void> _showScopeSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = ref.read(skillsControllerProvider);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final scope in state.scopes)
                ListTile(
                  leading: Icon(_scopeIcon(scope)),
                  title: Text(scope.label),
                  subtitle: scope.description.isEmpty
                      ? null
                      : Text(scope.description),
                  trailing: scope.id == state.selectedScopeId
                      ? const Icon(Icons.check)
                      : scope.readonly
                      ? const Icon(Icons.lock_outline)
                      : null,
                  onTap: () => Navigator.of(context).pop(scope.id),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await _selectScope(selected);
  }

  Future<void> _openEditor({ManagedSkill? initial}) async {
    final draft = await showDialog<SkillDraft>(
      context: context,
      builder: (context) => _SkillEditorDialog(initial: initial),
    );
    if (draft == null || !mounted) return;

    final notifier = ref.read(skillsControllerProvider.notifier);
    try {
      if (initial == null) {
        await notifier.create(draft);
      } else {
        await notifier.update(initial.id, draft);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              initial == null
                  ? context.l10n.skillsCreated
                  : context.l10n.skillsSaved,
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  Future<void> _editSkill(ManagedSkill skill) async {
    final detail = await ref
        .read(skillsControllerProvider.notifier)
        .loadDetail(skill.id);
    if (!mounted || detail == null) return;
    await _openEditor(initial: detail);
  }

  Future<void> _toggleSkill(ManagedSkill skill, bool enabled) async {
    if (!enabled && _isGlobalManagedAction(skill)) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_localized(context, 'Disable managed skill?', '禁用托管技能？')),
          content: Text(
            _localized(
              context,
              'Disabling ${skill.name} in Clawke Library affects all gateways that use this library.',
              '在 Clawke Library 禁用 ${skill.name} 会影响所有使用该库的 gateway。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.skillsStatusDisabled),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    try {
      await ref
          .read(skillsControllerProvider.notifier)
          .setEnabled(skill.id, enabled);
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  Future<void> _deleteSkill(ManagedSkill skill) async {
    final message = _isGlobalManagedAction(skill)
        ? _localized(
            context,
            '${context.l10n.skillsDeleteMessage(skill.name)} This affects all gateways that use Clawke Library.',
            '${context.l10n.skillsDeleteMessage(skill.name)} 这会影响所有使用 Clawke Library 的 gateway。',
          )
        : context.l10n.skillsDeleteMessage(skill.name);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.skillsDeleteTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(skillsControllerProvider.notifier).delete(skill.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.skillsDeleted),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  bool _isGlobalManagedAction(ManagedSkill skill) {
    final scope = ref.read(skillsControllerProvider).selectedScope;
    return skill.source == 'managed' || scope?.isLibrary == true;
  }
}

IconData _scopeIcon(SkillScope scope) {
  if (scope.isLibrary) return Icons.local_library_outlined;
  if (scope.isAllGateways) return Icons.hub_outlined;
  return Icons.account_tree_outlined;
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}

class _ScopeSidebar extends StatelessWidget {
  final List<SkillScope> scopes;
  final String? selectedScopeId;
  final bool isLoading;
  final ValueChanged<String> onSelected;

  const _ScopeSidebar({
    required this.scopes,
    required this.selectedScopeId,
    required this.isLoading,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _localized(context, 'Management Scope', '管理作用域'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (scopes.isEmpty)
            Text(
              _localized(context, 'Legacy skills list', '旧版技能列表'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            for (final scope in scopes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ScopeTile(
                  scope: scope,
                  selected: scope.id == selectedScopeId,
                  enabled: !isLoading,
                  onTap: () => onSelected(scope.id),
                ),
              ),
        ],
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  final SkillScope scope;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _ScopeTile({
    required this.scope,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                _scopeIcon(scope),
                color: selected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scope.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    if (scope.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        scope.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (scope.readonly)
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileScopeSelector extends StatelessWidget {
  final SkillScope? scope;
  final bool isReadOnly;
  final VoidCallback onTap;

  const _MobileScopeSelector({
    required this.scope,
    required this.isReadOnly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = scope?.label ?? _localized(context, 'Skills', '技能');
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(scope == null ? Icons.tune : _scopeIcon(scope!)),
        label: Text(label),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int enabled;
  final bool isLoading;
  final bool isReadOnly;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _Header({
    required this.total,
    required this.enabled,
    required this.isLoading,
    required this.isReadOnly,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.extension,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.navSkills,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.skillsPageSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricChip(label: context.l10n.skillsMetricAll, value: '$total'),
            _MetricChip(
              label: context.l10n.skillsMetricEnabled,
              value: '$enabled',
            ),
            IconButton.filledTonal(
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: context.l10n.skillsRefresh,
            ),
            FilledButton.icon(
              onPressed: isReadOnly ? null : onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.skillsNewSkill),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        '$label $value',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _SkillStatusFilter filter;
  final _SkillSourceFilter sourceFilter;
  final ValueChanged<_SkillStatusFilter> onFilterChanged;
  final ValueChanged<_SkillSourceFilter> onSourceFilterChanged;
  final ValueChanged<String> onChanged;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.sourceFilter,
    required this.onFilterChanged,
    required this.onSourceFilterChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: context.l10n.searchSkills,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          FilterChip(
            label: Text(context.l10n.skillsStatusAll),
            selected: filter == _SkillStatusFilter.all,
            onSelected: (_) => onFilterChanged(_SkillStatusFilter.all),
          ),
          FilterChip(
            label: Text(context.l10n.skillsStatusEnabled),
            selected: filter == _SkillStatusFilter.enabled,
            onSelected: (_) => onFilterChanged(_SkillStatusFilter.enabled),
          ),
          FilterChip(
            label: Text(context.l10n.skillsStatusDisabled),
            selected: filter == _SkillStatusFilter.disabled,
            onSelected: (_) => onFilterChanged(_SkillStatusFilter.disabled),
          ),
          FilterChip(
            label: Text(context.l10n.skillsSourceAll),
            selected: sourceFilter == _SkillSourceFilter.all,
            onSelected: (_) => onSourceFilterChanged(_SkillSourceFilter.all),
          ),
          FilterChip(
            label: Text(context.l10n.skillsSourceManaged),
            selected: sourceFilter == _SkillSourceFilter.managed,
            onSelected: (_) =>
                onSourceFilterChanged(_SkillSourceFilter.managed),
          ),
          FilterChip(
            label: Text(context.l10n.skillsSourceExternal),
            selected: sourceFilter == _SkillSourceFilter.external,
            onSelected: (_) =>
                onSourceFilterChanged(_SkillSourceFilter.external),
          ),
          FilterChip(
            label: Text(context.l10n.skillsSourceReadonly),
            selected: sourceFilter == _SkillSourceFilter.readonly,
            onSelected: (_) =>
                onSourceFilterChanged(_SkillSourceFilter.readonly),
          ),
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final ManagedSkill skill;
  final bool isBusy;
  final bool isToggleBusy;
  final bool readOnlyScope;
  final void Function(ManagedSkill skill, bool enabled) onToggle;
  final ValueChanged<ManagedSkill> onEdit;
  final ValueChanged<ManagedSkill> onDelete;

  const _SkillCard({
    required this.skill,
    required this.isBusy,
    required this.isToggleBusy,
    required this.readOnlyScope,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = skill.enabled ? colorScheme.primary : colorScheme.outline;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.bolt, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            skill.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          _Tag(label: skill.category),
                          _Tag(label: skill.sourceLabel),
                          if (skill.hasConflict)
                            _Tag(
                              label: context.l10n.skillsConflict,
                              color: colorScheme.errorContainer,
                              foreground: colorScheme.onErrorContainer,
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        skill.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (skill.trigger != null &&
                          skill.trigger!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.skillsTriggerLabel(skill.trigger!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: skill.enabled,
                  onChanged: readOnlyScope || isToggleBusy
                      ? null
                      : (enabled) => onToggle(skill, enabled),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: skill.writable && !readOnlyScope && !isBusy
                      ? () => onEdit(skill)
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.l10n.edit),
                ),
                OutlinedButton.icon(
                  onPressed: skill.deletable && !readOnlyScope && !isBusy
                      ? () => onDelete(skill)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.l10n.delete),
                ),
                TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(skill.path),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? foreground;

  const _Tag({required this.label, this.color, this.foreground});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground ?? colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SkillEditorDialog extends StatefulWidget {
  final ManagedSkill? initial;

  const _SkillEditorDialog({this.initial});

  @override
  State<_SkillEditorDialog> createState() => _SkillEditorDialogState();
}

class _SkillEditorDialogState extends State<_SkillEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _triggerController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    final skill = widget.initial;
    _nameController = TextEditingController(text: skill?.name ?? '');
    _categoryController = TextEditingController(
      text: skill?.category ?? 'general',
    );
    _descriptionController = TextEditingController(
      text: skill?.description ?? '',
    );
    _triggerController = TextEditingController(text: skill?.trigger ?? '');
    _bodyController = TextEditingController(
      text:
          skill?.body ??
          '## Purpose\n\nDescribe what this skill does and when to use it.\n',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _triggerController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.initial != null;
    final l10n = context.l10n;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.edit_note, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEditing
                              ? l10n.skillsEditTitle
                              : l10n.skillsNewSkill,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 240,
                        child: TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: l10n.skillsFieldName,
                            hintText: 'web-search',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => _validatePathPart(value, l10n),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          controller: _categoryController,
                          decoration: InputDecoration(
                            labelText: l10n.skillsFieldCategory,
                            hintText: 'general',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) => _validatePathPart(value, l10n),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextFormField(
                          controller: _triggerController,
                          decoration: InputDecoration(
                            labelText: l10n.skillsFieldTrigger,
                            hintText: 'Use when...',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: InputDecoration(
                      labelText: l10n.skillsFieldDescription,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n.skillsDescriptionRequired
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _bodyController,
                    minLines: 10,
                    maxLines: 18,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: l10n.skillsSkillMdBody,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.save),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validatePathPart(String? value, AppLocalizations l10n) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return l10n.skillsFieldRequired;
    if (text == '.' ||
        text == '..' ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)) {
      return l10n.skillsPathPartInvalid;
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      SkillDraft(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim(),
        trigger: _triggerController.text.trim(),
        body: _bodyController.text,
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Center(
        child: Text(
          context.l10n.noSkillsAvailable,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
