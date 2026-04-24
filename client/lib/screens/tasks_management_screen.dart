import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/providers/ws_state_provider.dart';

enum _TaskStatusFilter { all, enabled, disabled, error }

class TasksManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const TasksManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<TasksManagementScreen> createState() =>
      _TasksManagementScreenState();
}

class _TasksManagementScreenState extends ConsumerState<TasksManagementScreen> {
  final _searchController = TextEditingController();
  _TaskStatusFilter _statusFilter = _TaskStatusFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncConnectedAccounts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TasksState>(tasksControllerProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null && message != previous?.errorMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    });

    ref.listen<List<ConnectedAccount>>(connectedAccountsProvider, (_, __) {
      _syncConnectedAccounts();
    });

    final state = ref.watch(tasksControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final list = RefreshIndicator(
            onRefresh: () =>
                ref.read(tasksControllerProvider.notifier).refresh(),
            child: _buildTaskList(state, compact: !wide),
          );

          if (!wide) return list;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GatewaySidebar(
                accounts: state.accounts,
                selectedAccountId: state.selectedAccountId,
                isLoading: state.isLoading,
                onSelected: _selectAccount,
              ),
              Expanded(child: list),
              _RunsPane(
                state: state,
                onLoadOutput: (run) =>
                    ref.read(tasksControllerProvider.notifier).loadOutput(run),
              ),
            ],
          );
        },
      ),
    );

    if (!widget.showAppBar) return content;

    return Scaffold(
      appBar: AppBar(
        title: Text(_localized(context, 'Tasks', '任务管理')),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: content,
    );
  }

  Future<void> _syncConnectedAccounts() async {
    final accounts = ref
        .read(connectedAccountsProvider)
        .map(
          (account) => TaskAccount(
            accountId: account.accountId,
            agentName: account.agentName,
          ),
        )
        .toList();
    await ref.read(tasksControllerProvider.notifier).syncAccounts(accounts);
  }

  List<ManagedTask> _filtered(List<ManagedTask> tasks) {
    final query = _searchController.text.trim().toLowerCase();
    return tasks.where((task) {
      final matchesStatus = switch (_statusFilter) {
        _TaskStatusFilter.all => true,
        _TaskStatusFilter.enabled => task.enabled,
        _TaskStatusFilter.disabled => !task.enabled,
        _TaskStatusFilter.error => task.status == 'error',
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return task.name.toLowerCase().contains(query) ||
          task.schedule.toLowerCase().contains(query) ||
          task.prompt.toLowerCase().contains(query) ||
          task.skills.any((skill) => skill.toLowerCase().contains(query));
    }).toList();
  }

  Widget _buildTaskList(TasksState state, {required bool compact}) {
    final filteredTasks = _filtered(state.tasks);
    final showDisconnected = state.accounts.isEmpty;
    final showLoading = state.isLoading && state.tasks.isEmpty;
    final showEmpty =
        !showDisconnected && !showLoading && filteredTasks.isEmpty;
    final hasMobileGatewaySelector = compact && state.accounts.isNotEmpty;
    final leadingCount = hasMobileGatewaySelector ? 6 : 4;
    final itemCount = showDisconnected || showLoading || showEmpty
        ? leadingCount + 1
        : filteredTasks.length + leadingCount;

    return ListView.builder(
      padding: EdgeInsets.all(compact ? 16 : 28),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasMobileGatewaySelector) {
          if (index == 0) {
            return _MobileGatewaySelector(
              account: state.selectedAccount,
              onTap: _showGatewaySheet,
            );
          }
          if (index == 1) return const SizedBox(height: 18);
          index -= 2;
        }

        if (index == 0) {
          return _Header(
            total: state.tasks.length,
            enabled: state.tasks.where((task) => task.enabled).length,
            running: state.tasks
                .where((task) => task.lastRun?.status == 'running')
                .length,
            isLoading: state.isLoading,
            canCreate: state.selectedAccountId != null,
            onCreate: () => _openEditor(),
            onRefresh: () =>
                ref.read(tasksControllerProvider.notifier).refresh(),
          );
        }
        if (index == 1 || index == 3) return const SizedBox(height: 18);
        if (index == 2) {
          return _Toolbar(
            controller: _searchController,
            filter: _statusFilter,
            onFilterChanged: (filter) => setState(() => _statusFilter = filter),
            onChanged: (_) => setState(() {}),
          );
        }
        if (showDisconnected) return const _DisconnectedPanel();
        if (showLoading) return const _LoadingPanel();
        if (showEmpty) return const _EmptyPanel();

        final task = filteredTasks[index - 4];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _TaskCard(
            task: task,
            selected: state.selectedTask?.id == task.id,
            isBusy: state.busyTaskIds.contains(task.id),
            isToggleBusy: state.togglingTaskIds.contains(task.id),
            onToggle: _toggleTask,
            onEdit: _editTask,
            onDelete: _deleteTask,
            onRun: _runTask,
            onRuns: _showRuns,
          ),
        );
      },
    );
  }

  Future<void> _selectAccount(String accountId) async {
    await ref.read(tasksControllerProvider.notifier).selectAccount(accountId);
  }

  Future<void> _showGatewaySheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final state = ref.read(tasksControllerProvider);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final account in state.accounts)
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(account.agentName),
                  subtitle: Text(account.accountId),
                  trailing: account.accountId == state.selectedAccountId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(account.accountId),
                ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    await _selectAccount(selected);
  }

  Future<void> _openEditor({ManagedTask? initial}) async {
    final accountId =
        initial?.accountId ??
        ref.read(tasksControllerProvider).selectedAccountId;
    if (accountId == null) return;

    final draft = await showDialog<TaskDraft>(
      context: context,
      builder: (context) =>
          _TaskEditorDialog(accountId: accountId, initial: initial),
    );
    if (draft == null || !mounted) return;

    final notifier = ref.read(tasksControllerProvider.notifier);
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
                  ? _localized(context, 'Task created', '任务已创建')
                  : _localized(context, 'Task saved', '任务已保存'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Provider listener displays the API error.
    }
  }

  Future<void> _editTask(ManagedTask task) => _openEditor(initial: task);

  Future<void> _toggleTask(ManagedTask task, bool enabled) async {
    try {
      await ref
          .read(tasksControllerProvider.notifier)
          .setEnabled(task, enabled);
    } catch (_) {
      // Provider listener displays the API error.
    }
  }

  Future<void> _deleteTask(ManagedTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_localized(context, 'Delete task?', '删除任务？')),
        content: Text(
          _localized(
            context,
            'Delete ${task.name}? The agent-side schedule will be removed.',
            '确定删除 ${task.name}？agent 侧的计划任务会被移除。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_localized(context, 'Cancel', '取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_localized(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(tasksControllerProvider.notifier).delete(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localized(context, 'Task deleted', '任务已删除')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Provider listener displays the API error.
    }
  }

  Future<void> _runTask(ManagedTask task) async {
    try {
      await ref.read(tasksControllerProvider.notifier).runNow(task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localized(context, 'Task triggered', '已触发任务')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Provider listener displays the API error.
    }
  }

  Future<void> _showRuns(ManagedTask task) async {
    await ref.read(tasksControllerProvider.notifier).loadRuns(task);
    if (!mounted) return;
    final wide = MediaQuery.of(context).size.width >= 980;
    if (wide) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Consumer(
          builder: (context, ref, _) => _RunsPane(
            state: ref.watch(tasksControllerProvider),
            onLoadOutput: (run) =>
                ref.read(tasksControllerProvider.notifier).loadOutput(run),
          ),
        ),
      ),
    );
  }
}

class _GatewaySidebar extends StatelessWidget {
  final List<TaskAccount> accounts;
  final String? selectedAccountId;
  final bool isLoading;
  final ValueChanged<String> onSelected;

  const _GatewaySidebar({
    required this.accounts,
    required this.selectedAccountId,
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
            _localized(context, 'Gateways', 'Gateway 列表'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (accounts.isEmpty)
            Text(
              _localized(context, 'No gateway connected', '暂无已连接 Gateway'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            )
          else
            for (final account in accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GatewayTile(
                  account: account,
                  selected: account.accountId == selectedAccountId,
                  enabled: !isLoading,
                  onTap: () => onSelected(account.accountId),
                ),
              ),
        ],
      ),
    );
  }
}

class _GatewayTile extends StatelessWidget {
  final TaskAccount account;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _GatewayTile({
    required this.account,
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.hub_outlined,
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
                      account.agentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account.accountId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileGatewaySelector extends StatelessWidget {
  final TaskAccount? account;
  final VoidCallback onTap;

  const _MobileGatewaySelector({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        account?.agentName ?? _localized(context, 'Gateways', 'Gateway');
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.hub_outlined),
        label: Text(label),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int total;
  final int enabled;
  final int running;
  final bool isLoading;
  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _Header({
    required this.total,
    required this.enabled,
    required this.running,
    required this.isLoading,
    required this.canCreate,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _localized(context, 'Task Management', '任务管理'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _localized(
            context,
            'Manage agent-side schedules, manual triggers, run history, and outputs.',
            '管理 agent 侧任务的生命周期、手动触发、执行记录和结果。',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetricChip(
              label: _localized(context, 'All', '全部'),
              value: '$total',
            ),
            _MetricChip(
              label: _localized(context, 'Enabled', '启用'),
              value: '$enabled',
            ),
            _MetricChip(
              label: _localized(context, 'Running', '运行中'),
              value: '$running',
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(_localized(context, 'Refresh', '刷新')),
            ),
            FilledButton.icon(
              onPressed: canCreate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: Text(_localized(context, 'New Task', '新建任务')),
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
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _TaskStatusFilter filter;
  final ValueChanged<_TaskStatusFilter> onFilterChanged;
  final ValueChanged<String> onChanged;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.onFilterChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
              prefixIcon: const Icon(Icons.search),
              hintText: _localized(context, 'Search tasks', '搜索任务'),
              isDense: true,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
        ),
        SegmentedButton<_TaskStatusFilter>(
          selected: {filter},
          onSelectionChanged: (selected) => onFilterChanged(selected.first),
          segments: [
            ButtonSegment(
              value: _TaskStatusFilter.all,
              label: Text(_localized(context, 'All', '全部')),
            ),
            ButtonSegment(
              value: _TaskStatusFilter.enabled,
              label: Text(_localized(context, 'Enabled', '已启用')),
            ),
            ButtonSegment(
              value: _TaskStatusFilter.disabled,
              label: Text(_localized(context, 'Paused', '已暂停')),
            ),
            ButtonSegment(
              value: _TaskStatusFilter.error,
              label: Text(_localized(context, 'Error', '异常')),
            ),
          ],
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ManagedTask task;
  final bool selected;
  final bool isBusy;
  final bool isToggleBusy;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onEdit;
  final ValueChanged<ManagedTask> onDelete;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskCard({
    required this.task,
    required this.selected,
    required this.isBusy,
    required this.isToggleBusy,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme, task.status, task.enabled);
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => onRuns(task),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.task_alt, color: statusColor, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.name.isEmpty ? task.id : task.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.scheduleText ?? task.schedule,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (isBusy || isToggleBusy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Switch(
                      value: task.enabled,
                      onChanged: (value) => onToggle(task, value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                task.prompt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusPill(
                    label: _statusLabel(context, task),
                    color: statusColor,
                  ),
                  if (task.nextRunAt != null)
                    _InfoPill(
                      icon: Icons.schedule,
                      text:
                          _localized(context, 'Next: ', '下次：') +
                          task.nextRunAt!,
                    ),
                  if (task.lastRun != null)
                    _InfoPill(
                      icon: Icons.history,
                      text:
                          _localized(context, 'Last: ', '最近：') +
                          _runStatusLabel(context, task.lastRun!.status),
                    ),
                  for (final skill in task.skills.take(3))
                    _InfoPill(icon: Icons.extension_outlined, text: skill),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => onRun(task),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_localized(context, 'Run', '运行')),
                  ),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : () => onRuns(task),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(_localized(context, 'Runs', '记录')),
                  ),
                  IconButton(
                    tooltip: _localized(context, 'Edit', '编辑'),
                    onPressed: isBusy ? null : () => onEdit(task),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: _localized(context, 'Delete', '删除'),
                    onPressed: isBusy ? null : () => onDelete(task),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunsPane extends StatelessWidget {
  final TasksState state;
  final ValueChanged<TaskRun> onLoadOutput;

  const _RunsPane({required this.state, required this.onLoadOutput});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localized(context, 'Run History', '执行记录'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (state.selectedTask != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    state.selectedTask!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: state.selectedTask == null
                ? Center(
                    child: Text(
                      _localized(context, 'Select a task', '选择一个任务'),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : state.isLoadingRuns
                ? const Center(child: CircularProgressIndicator())
                : state.runs.isEmpty
                ? Center(
                    child: Text(
                      _localized(context, 'No runs yet', '暂无执行记录'),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.runs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final run = state.runs[index];
                      return _RunTile(run: run, onTap: () => onLoadOutput(run));
                    },
                  ),
          ),
          if (state.selectedRunOutput != null) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(12),
              color: colorScheme.surface,
              child: SingleChildScrollView(
                child: SelectableText(
                  state.selectedRunOutput!.isEmpty
                      ? _localized(context, 'Loading output...', '正在加载结果...')
                      : state.selectedRunOutput!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final TaskRun run;
  final VoidCallback onTap;

  const _RunTile({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _runColor(colorScheme, run.status);
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(Icons.circle, color: color, size: 12),
        title: Text(_runStatusLabel(context, run.status)),
        subtitle: Text(
          [
            run.startedAt,
            if (run.outputPreview != null && run.outputPreview!.isNotEmpty)
              run.outputPreview!,
            if (run.error != null && run.error!.isNotEmpty) run.error!,
          ].join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskEditorDialog extends StatefulWidget {
  final String accountId;
  final ManagedTask? initial;

  const _TaskEditorDialog({required this.accountId, this.initial});

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  late final TextEditingController _skillsController;
  late final TextEditingController _deliverController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _scheduleController = TextEditingController(text: initial?.schedule ?? '');
    _promptController = TextEditingController(text: initial?.prompt ?? '');
    _skillsController = TextEditingController(
      text: initial?.skills.join(', ') ?? '',
    );
    _deliverController = TextEditingController(text: initial?.deliver ?? '');
    _enabled = initial?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    _skillsController.dispose();
    _deliverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? _localized(context, 'New Task', '新建任务')
            : _localized(context, 'Edit Task', '编辑任务'),
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.accountId,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Name', '名称'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _scheduleController,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Schedule', '计划'),
                    hintText: '0 9 * * *',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? _localized(context, 'Required', '必填')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _promptController,
                  minLines: 6,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Prompt', '任务提示词'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? _localized(context, 'Required', '必填')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skillsController,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Skills', '技能'),
                    hintText: _localized(
                      context,
                      'Comma separated skill ids',
                      '用逗号分隔技能 ID',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deliverController,
                  decoration: InputDecoration(
                    labelText: _localized(context, 'Delivery', '交付方式'),
                    hintText: _localized(context, 'Optional', '可选'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                  contentPadding: EdgeInsets.zero,
                  title: Text(_localized(context, 'Enabled', '启用')),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_localized(context, 'Cancel', '取消')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_localized(context, 'Save', '保存')),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final skills = _skillsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    Navigator.of(context).pop(
      TaskDraft(
        accountId: widget.accountId,
        name: _nameController.text,
        schedule: _scheduleController.text,
        prompt: _promptController.text,
        enabled: _enabled,
        skills: skills,
        deliver: _deliverController.text.trim().isEmpty
            ? null
            : _deliverController.text.trim(),
      ),
    );
  }
}

class _DisconnectedPanel extends StatelessWidget {
  const _DisconnectedPanel();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.hub_outlined,
      title: _localized(context, 'No gateway connected', '暂无已连接 Gateway'),
      message: _localized(
        context,
        'Task management becomes available after Hermes or OpenClaw connects.',
        'Hermes 或 OpenClaw 连接后即可管理任务。',
      ),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: Icons.task_alt,
      title: _localized(context, 'No tasks', '暂无任务'),
      message: _localized(
        context,
        'Create an agent-side task to manage its schedule and runs.',
        '新建一个 agent 侧任务后，可以在这里管理计划和执行记录。',
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(ColorScheme colorScheme, String status, bool enabled) {
  if (!enabled) return colorScheme.outline;
  return switch (status) {
    'error' => colorScheme.error,
    'paused' || 'disabled' => colorScheme.outline,
    _ => colorScheme.primary,
  };
}

Color _runColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'failed' => colorScheme.error,
    'cancelled' => colorScheme.outline,
    'running' => colorScheme.tertiary,
    _ => colorScheme.primary,
  };
}

String _statusLabel(BuildContext context, ManagedTask task) {
  if (!task.enabled) return _localized(context, 'Paused', '已暂停');
  return switch (task.status) {
    'error' => _localized(context, 'Error', '异常'),
    'paused' || 'disabled' => _localized(context, 'Paused', '已暂停'),
    _ => _localized(context, 'Active', '运行中'),
  };
}

String _runStatusLabel(BuildContext context, String status) {
  return switch (status) {
    'running' => _localized(context, 'Running', '运行中'),
    'failed' => _localized(context, 'Failed', '失败'),
    'cancelled' => _localized(context, 'Cancelled', '已取消'),
    _ => _localized(context, 'Success', '成功'),
  };
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}
