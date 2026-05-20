import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:client/data/database/app_database.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/models/task_delivery_validation.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/widgets/app_floating_notice.dart';
import 'package:client/widgets/app_snack_bar.dart';
import 'package:client/widgets/copyable_text.dart';
import 'package:client/widgets/empty_state_panel.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:client/widgets/gateway_unavailable_panel.dart';

enum _TaskStatusFilter { all, enabled, running, error }

enum _TaskPage { list, detail, edit, runs, runOutput }

enum _TaskRunsBackTarget { list, detail }

enum _TaskScheduleMode { daily, weekly, monthly, frequent, advanced }

enum _TaskFrequencyUnit { minute, hour }

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
  _TaskPage _page = _TaskPage.list;
  _TaskRunsBackTarget _runsBackTarget = _TaskRunsBackTarget.detail;
  String? _activeTaskId;
  String? _activeRunId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGatewayCache();
      _syncGateways();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<GatewayInfo>>>(gatewayListProvider, (_, next) {
      final gateways = next.valueOrNull;
      if (gateways != null) unawaited(_syncGateways(gateways));
    });

    final state = ref.watch(tasksControllerProvider);
    final gateways =
        ref.watch(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final conversations =
        ref.watch(conversationListProvider).valueOrNull ??
        const <Conversation>[];
    final colorScheme = Theme.of(context).colorScheme;

    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final unavailableGateway = _selectedUnavailableGateway(
            gateways,
            state,
          );
          final body = _buildBody(
            state,
            gateways,
            conversations,
            unavailableGateway: unavailableGateway,
            compact: !wide,
          );
          final bodyWithNotice = _buildBodyWithErrorNotice(
            body,
            state,
            gateways,
            unavailableGateway: unavailableGateway,
          );

          if (!wide) return bodyWithNotice;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GatewaySelectorPane(
                gateways: gateways,
                selectedGatewayId: state.selectedAccountId,
                capability: 'tasks',
                errorGatewayId:
                    state.errorAccountId ?? unavailableGateway?.gatewayId,
                issueKeyPrefix: 'tasks_gateway_issue',
                onSelected: _selectAccount,
                onRename: (gatewayId, displayName) => ref
                    .read(gatewayRepositoryProvider)
                    .renameGateway(gatewayId, displayName),
              ),
              Expanded(child: bodyWithNotice),
            ],
          );
        },
      ),
    );

    if (!widget.showAppBar || _page != _TaskPage.list) return content;

    return Scaffold(appBar: _buildAppBar(state, gateways), body: content);
  }

  PreferredSizeWidget _buildAppBar(
    TasksState state,
    List<GatewayInfo> gateways,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final unavailableGateway = _selectedUnavailableGateway(gateways, state);
    final hasGatewayIssue =
        unavailableGateway != null || state.errorAccountId != null;
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: _localized(context, 'Back', '返回'),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      centerTitle: true,
      title: Text(_localized(context, 'Tasks', '任务管理')),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: _localized(context, 'Refresh', '刷新'),
          onPressed: state.isLoading || hasGatewayIssue
              ? null
              : () => unawaited(_refreshTasks(gateways)),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: _localized(context, 'New Task', '新建任务'),
          onPressed: state.selectedAccountId == null || hasGatewayIssue
              ? null
              : () => _openEditor(),
        ),
      ],
    );
  }

  void _refreshGatewayCache() {
    unawaited(
      ref
          .read(gatewayRepositoryProvider)
          .syncFromServer()
          .catchError(
            (Object error, StackTrace stackTrace) =>
                debugPrint('[Gateway] ⚠️ sync failed: $error'),
          ),
    );
  }

  Future<void> _syncGateways([List<GatewayInfo>? gateways]) async {
    final source =
        gateways ??
        ref.read(gatewayListProvider).valueOrNull ??
        const <GatewayInfo>[];
    final state = ref.read(tasksControllerProvider);
    final ordered = orderGatewaysForSelection(
      source,
      'tasks',
      currentGatewayId: state.selectedAccountId,
    );
    final accounts = _taskAccountsFromGateways(
      ordered
          .where((gateway) => !gatewayUnavailableFor(gateway, 'tasks'))
          .toList(),
    );
    await ref.read(tasksControllerProvider.notifier).syncAccounts(accounts);
  }

  Future<void> _refreshTasks(List<GatewayInfo> gateways) {
    final state = ref.read(tasksControllerProvider);
    final selected = gatewayById(gateways, state.selectedAccountId);
    if (selected != null && gatewayUnavailableFor(selected, 'tasks')) {
      _markTasksGatewayUnavailable(
        _taskAccountsFromGateways(
          orderGatewaysForSelection(
            gateways,
            'tasks',
            currentGatewayId: selected.gatewayId,
          ),
        ),
        selected,
      );
      return Future.value();
    }
    return ref.read(tasksControllerProvider.notifier).refresh();
  }

  List<ManagedTask> _filtered(List<ManagedTask> tasks) {
    final query = _searchController.text.trim().toLowerCase();
    return tasks.where((task) {
      final matchesStatus = switch (_statusFilter) {
        _TaskStatusFilter.all => true,
        _TaskStatusFilter.enabled => task.enabled,
        _TaskStatusFilter.running => _isTaskRunning(task),
        _TaskStatusFilter.error => _isTaskError(task),
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      return task.name.toLowerCase().contains(query) ||
          task.schedule.toLowerCase().contains(query) ||
          task.prompt.toLowerCase().contains(query) ||
          (_taskSkillsSupported(task.agent) &&
              task.skills.any((skill) => skill.toLowerCase().contains(query)));
    }).toList();
  }

  ManagedTask? _activeTask(TasksState state) {
    final id = _activeTaskId;
    if (id == null) return state.selectedTask;
    for (final task in state.tasks) {
      if (task.id == id) return task;
    }
    if (state.selectedTask?.id == id) return state.selectedTask;
    return null;
  }

  TaskRun? _activeRun(TasksState state) {
    final id = _activeRunId;
    if (id == null) return null;
    for (final run in state.runs) {
      if (run.id == id) return run;
    }
    return null;
  }

  void _showList() {
    setState(() {
      _page = _TaskPage.list;
      _runsBackTarget = _TaskRunsBackTarget.detail;
      _activeTaskId = null;
      _activeRunId = null;
    });
  }

  void _showDetail(ManagedTask task) {
    setState(() {
      _page = _TaskPage.detail;
      _activeTaskId = task.id;
      _activeRunId = null;
    });
  }

  Widget _buildBody(
    TasksState state,
    List<GatewayInfo> gateways,
    List<Conversation> conversations, {
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    if (_page == _TaskPage.list) {
      return RefreshIndicator(
        onRefresh: () => _refreshTasks(gateways),
        child: _buildTaskList(
          state,
          gateways,
          conversations: conversations,
          unavailableGateway: unavailableGateway,
          compact: compact,
        ),
      );
    }

    final task = _page == _TaskPage.edit && _activeTaskId == null
        ? null
        : _activeTask(state);
    if (_page == _TaskPage.edit) {
      final accountId =
          task?.accountId ??
          state.selectedAccountId ??
          (state.accounts.isEmpty ? null : state.accounts.first.accountId);
      if (accountId == null) {
        return _buildTaskList(
          state,
          gateways,
          conversations: conversations,
          unavailableGateway: unavailableGateway,
          compact: compact,
        );
      }
      final gateway = gatewayById(gateways, accountId);
      return _TaskEditPage(
        accountId: accountId,
        gatewayType: gateway?.gatewayType ?? task?.agent ?? accountId,
        initial: task,
        conversations: conversations,
        isSaving:
            state.isSaving ||
            (task != null && state.busyTaskIds.contains(task.id)),
        onCancel: () => task == null ? _showList() : _showDetail(task),
        onSave: (draft) => _saveTask(draft, initial: task),
        onDelete: task == null ? null : () => _confirmDeleteTask(task),
      );
    }

    if (task == null) {
      return _buildTaskList(
        state,
        gateways,
        conversations: conversations,
        unavailableGateway: unavailableGateway,
        compact: compact,
      );
    }

    if (_page == _TaskPage.runs) {
      return _TaskRunsPage(
        task: task,
        state: state,
        conversations: conversations,
        onBack: () => _backFromRuns(task),
        onOpenOutput: _showRunOutput,
      );
    }

    if (_page == _TaskPage.runOutput) {
      final run = _activeRun(state);
      if (run == null) {
        return _TaskRunsPage(
          task: task,
          state: state,
          conversations: conversations,
          onBack: () => _backFromRuns(task),
          onOpenOutput: _showRunOutput,
        );
      }
      return _TaskRunOutputPage(
        task: task,
        run: run,
        output: state.selectedRunOutput,
        conversations: conversations,
        onBack: () => _showRuns(task, backTarget: _runsBackTarget),
      );
    }

    return _TaskDetailPage(
      task: task,
      conversations: conversations,
      onBack: _showList,
      onEdit: () => _openEditor(initial: task),
      onRun: () => _runTask(task),
      onRuns: () => _showRuns(task),
    );
  }

  Widget _buildBodyWithErrorNotice(
    Widget body,
    TasksState state,
    List<GatewayInfo> gateways, {
    GatewayInfo? unavailableGateway,
  }) {
    final showErrorNotice = _shouldShowErrorNotice(
      state,
      gateways,
      unavailableGateway,
    );
    if (!showErrorNotice) return body;

    return Stack(
      children: [
        Positioned.fill(child: body),
        AppFloatingNotice.error(
          message: state.errorMessage!,
          onDismiss: () =>
              ref.read(tasksControllerProvider.notifier).clearError(),
        ),
      ],
    );
  }

  Widget _buildTaskList(
    TasksState state,
    List<GatewayInfo> gateways, {
    required List<Conversation> conversations,
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    final filteredTasks = _filtered(state.tasks);
    final showUnavailablePanel = unavailableGateway != null;
    final showDisconnected = !showUnavailablePanel && state.accounts.isEmpty;
    final showLoading =
        !showUnavailablePanel && state.isLoading && state.tasks.isEmpty;
    final showEmpty =
        !showUnavailablePanel &&
        !showDisconnected &&
        !showLoading &&
        filteredTasks.isEmpty;
    final hasMobileGatewaySelector = compact && gateways.isNotEmpty;

    if (!showUnavailablePanel &&
        (showDisconnected || showLoading || showEmpty)) {
      return _buildTaskStateList(
        state,
        gateways,
        compact: compact,
        showDisconnected: showDisconnected,
        showLoading: showLoading,
      );
    }

    final padding = compact ? 16.0 : 28.0;
    final toolbar = _Toolbar(
      controller: _searchController,
      filter: _statusFilter,
      compact: compact,
      total: state.tasks.length,
      enabled: state.tasks.where((task) => task.enabled).length,
      running: state.tasks.where(_isTaskRunning).length,
      error: state.tasks.where(_isTaskError).length,
      onFilterChanged: (filter) => setState(() => _statusFilter = filter),
      onChanged: (_) => setState(() {}),
    );
    final topItems = <Widget>[
      if (hasMobileGatewaySelector) ...[
        GatewayMobileSelectorButton(
          gateways: gateways,
          selectedGatewayId: state.selectedAccountId,
          capability: 'tasks',
          errorGatewayId: state.errorAccountId ?? unavailableGateway?.gatewayId,
          issueKeyPrefix: 'tasks_gateway_issue',
          onSelected: _selectAccount,
        ),
        const SizedBox(height: 18),
      ],
      _Header(
        isLoading: state.isLoading,
        canCreate: state.selectedAccountId != null && !showUnavailablePanel,
        hasGatewayIssue: showUnavailablePanel || state.errorAccountId != null,
        compact: compact && widget.showAppBar,
        onCreate: () => _openEditor(),
        onRefresh: () => unawaited(_refreshTasks(gateways)),
      ),
      const SizedBox(height: 18),
      toolbar,
      const SizedBox(height: 12),
      if (!showUnavailablePanel)
        _ContentMeta(visibleCount: filteredTasks.length)
      else
        SizedBox(
          height: gatewayUnavailablePanelHeight(context, compact),
          child: GatewayUnavailablePanel(
            title: gatewayUnavailableTitle(
              context,
              unavailableGateway,
              capability: 'tasks',
              capabilityNameZh: '任务管理',
              capabilityNameEn: 'task management',
            ),
            message: _localized(
              context,
              'Reconnect the gateway to refresh tasks.',
              '连接恢复后，任务列表会自动刷新。',
            ),
            footnote: _localized(
              context,
              'No task request will be sent.',
              '当前不会发起任务请求',
            ),
          ),
        ),
      if (!showUnavailablePanel) const SizedBox(height: 12),
    ];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(left: padding, top: padding, right: padding),
          sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
        ),
        if (!showUnavailablePanel)
          SliverPadding(
            padding: EdgeInsets.only(
              left: padding,
              right: padding,
              bottom: padding,
            ),
            sliver: SliverToBoxAdapter(
              child: _TaskCardWrap(
                tasks: filteredTasks,
                conversations: conversations,
                compact: compact,
                selectedTaskId: state.selectedTask?.id,
                busyTaskIds: state.busyTaskIds,
                togglingTaskIds: state.togglingTaskIds,
                onOpen: _showDetail,
                onToggle: _toggleTask,
                onRun: _runTask,
                onRuns: _showRunsFromList,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTaskStateList(
    TasksState state,
    List<GatewayInfo> gateways, {
    required bool compact,
    required bool showDisconnected,
    required bool showLoading,
  }) {
    final padding = compact ? 16.0 : 28.0;
    final topItems = <Widget>[
      if (compact && gateways.isNotEmpty) ...[
        GatewayMobileSelectorButton(
          gateways: gateways,
          selectedGatewayId: state.selectedAccountId,
          capability: 'tasks',
          errorGatewayId: state.errorAccountId,
          issueKeyPrefix: 'tasks_gateway_issue',
          onSelected: _selectAccount,
        ),
        const SizedBox(height: 18),
      ],
      _Header(
        isLoading: state.isLoading,
        canCreate: state.selectedAccountId != null,
        hasGatewayIssue: state.errorAccountId != null,
        compact: compact && widget.showAppBar,
        onCreate: () => _openEditor(),
        onRefresh: () => unawaited(_refreshTasks(gateways)),
      ),
      const SizedBox(height: 18),
      _Toolbar(
        controller: _searchController,
        filter: _statusFilter,
        compact: compact,
        total: state.tasks.length,
        enabled: state.tasks.where((task) => task.enabled).length,
        running: state.tasks.where(_isTaskRunning).length,
        error: state.tasks.where(_isTaskError).length,
        onFilterChanged: (filter) => setState(() => _statusFilter = filter),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 18),
    ];
    final statePanel = showDisconnected
        ? const _DisconnectedPanel()
        : showLoading
        ? const _LoadingPanel()
        : const _EmptyPanel();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(left: padding, top: padding, right: padding),
          sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
            left: padding,
            right: padding,
            bottom: padding,
          ),
          sliver: SliverFillRemaining(hasScrollBody: false, child: statePanel),
        ),
      ],
    );
  }

  Future<void> _selectAccount(String accountId) async {
    final gateways =
        ref.read(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final gateway = gatewayById(gateways, accountId);
    if (gateway != null && gatewayUnavailableFor(gateway, 'tasks')) {
      _markTasksGatewayUnavailable(
        _taskAccountsFromGateways(
          orderGatewaysForSelection(
            gateways,
            'tasks',
            currentGatewayId: accountId,
          ),
        ),
        gateway,
      );
      return;
    }
    await ref.read(tasksControllerProvider.notifier).selectAccount(accountId);
    if (mounted) _showList();
  }

  GatewayInfo? _selectedUnavailableGateway(
    List<GatewayInfo> gateways,
    TasksState state,
  ) {
    final gateway = gatewayById(gateways, state.selectedAccountId);
    if (gateway == null || !gatewayUnavailableFor(gateway, 'tasks')) {
      return null;
    }
    return gateway;
  }

  bool _shouldShowErrorNotice(
    TasksState state,
    List<GatewayInfo> gateways,
    GatewayInfo? unavailableGateway,
  ) {
    final errorAccountId = state.errorAccountId;
    final errorGateway = gatewayById(gateways, errorAccountId);
    return state.errorMessage != null &&
        !(errorGateway != null &&
            gatewayUnavailableFor(errorGateway, 'tasks')) &&
        !(unavailableGateway != null &&
            errorAccountId == unavailableGateway.gatewayId);
  }

  List<TaskAccount> _taskAccountsFromGateways(List<GatewayInfo> gateways) {
    return gateways
        .where((gateway) => gateway.supports('tasks'))
        .map(
          (gateway) => TaskAccount(
            accountId: gateway.gatewayId,
            agentName: gateway.displayName,
          ),
        )
        .toList();
  }

  void _markTasksGatewayUnavailable(
    List<TaskAccount> accounts,
    GatewayInfo gateway,
  ) {
    ref
        .read(tasksControllerProvider.notifier)
        .selectUnavailableAccount(
          accounts,
          gateway.gatewayId,
          gatewayUnavailableStateMessage(context, gateway),
          showErrorMessage: false,
        );
  }

  void _openEditor({ManagedTask? initial}) {
    final accountId =
        initial?.accountId ??
        ref.read(tasksControllerProvider).selectedAccountId;
    if (accountId == null) return;
    setState(() {
      _page = _TaskPage.edit;
      _activeTaskId = initial?.id;
    });
  }

  Future<void> _saveTask(TaskDraft draft, {ManagedTask? initial}) async {
    final notifier = ref.read(tasksControllerProvider.notifier);
    try {
      if (initial == null) {
        await notifier.create(draft);
      } else {
        await notifier.update(initial.id, draft);
      }
      final savedTask = ref.read(tasksControllerProvider).selectedTask;
      if (mounted) {
        setState(() {
          _page = _TaskPage.detail;
          _activeTaskId = savedTask?.id ?? initial?.id;
        });
      }
      if (mounted) {
        showAppSnackBar(
          context,
          initial == null
              ? _localized(context, 'Task created', '任务已创建')
              : _localized(context, 'Task saved', '任务已保存'),
        );
      }
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _toggleTask(ManagedTask task, bool enabled) async {
    try {
      await ref
          .read(tasksControllerProvider.notifier)
          .setEnabled(task, enabled);
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _confirmDeleteTask(ManagedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localized(context, 'Delete task?', '删除任务？')),
        content: Text(
          _localized(
            context,
            'This will delete task ${task.name}. This action cannot be undone.\nContinue?',
            '将删除任务 ${task.name}，此操作不可撤销。\n是否继续？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_localized(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(_localized(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(tasksControllerProvider.notifier).delete(task);
      if (!mounted) return;
      _showList();
      showAppSnackBar(context, _localized(context, 'Task deleted', '任务已删除'));
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _runTask(ManagedTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_localized(context, 'Run task now?', '确认立即执行任务')),
        content: Text(
          _localized(
            context,
            'Task ${task.name} will be submitted to the current Gateway immediately.\nContinue?',
            '任务 ${task.name} 会立即提交到当前 Gateway 执行。\n是否继续？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_localized(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_localized(context, 'Confirm run', '确认执行')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(tasksControllerProvider.notifier).runNow(task);
      if (mounted) {
        showAppSnackBar(
          context,
          _localized(context, 'Task triggered', '已触发任务'),
        );
      }
    } catch (_) {
      // The persistent error panel displays the API error.
    }
  }

  Future<void> _showRunsFromList(ManagedTask task) {
    return _showRuns(task, backTarget: _TaskRunsBackTarget.list);
  }

  Future<void> _showRuns(
    ManagedTask task, {
    _TaskRunsBackTarget backTarget = _TaskRunsBackTarget.detail,
  }) async {
    setState(() {
      _page = _TaskPage.runs;
      _runsBackTarget = backTarget;
      _activeTaskId = task.id;
      _activeRunId = null;
    });
    await ref.read(tasksControllerProvider.notifier).loadRuns(task);
  }

  void _backFromRuns(ManagedTask task) {
    if (_runsBackTarget == _TaskRunsBackTarget.list) {
      _showList();
      return;
    }
    _showDetail(task);
  }

  Future<void> _showRunOutput(TaskRun run) async {
    setState(() {
      _page = _TaskPage.runOutput;
      _activeRunId = run.id;
    });
    await ref.read(tasksControllerProvider.notifier).loadOutput(run);
  }
}

class _Header extends StatelessWidget {
  final bool isLoading;
  final bool canCreate;
  final bool hasGatewayIssue;
  final bool compact;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _Header({
    required this.isLoading,
    required this.canCreate,
    required this.hasGatewayIssue,
    required this.compact,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox.shrink();

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
              Text(
                _localized(context, 'Task Management', '任务管理'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _localized(
                  context,
                  'Manage agent-side schedules, manual triggers, run history, and outputs.',
                  '管理 agent 侧任务的生命周期、手动触发、执行记录和结果。',
                ),
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
            IconButton.filledTonal(
              onPressed: isLoading || hasGatewayIssue ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: _localized(context, 'Refresh', '刷新'),
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

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _TaskStatusFilter filter;
  final bool compact;
  final int total;
  final int enabled;
  final int running;
  final int error;
  final ValueChanged<_TaskStatusFilter> onFilterChanged;
  final ValueChanged<String> onChanged;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.compact,
    required this.total,
    required this.enabled,
    required this.running,
    required this.error,
    required this.onFilterChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final searchTextStyle = theme.textTheme.bodyMedium;
    final filterTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    FilterChip filterChip({
      required String label,
      required bool selected,
      required VoidCallback onSelected,
      Key? key,
    }) {
      return FilterChip(
        key: key,
        label: Text(label),
        labelStyle: filterTextStyle,
        selected: selected,
        onSelected: (_) => onSelected(),
      );
    }

    if (!compact) {
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
                style: searchTextStyle,
                decoration: InputDecoration(
                  hintText: _localized(context, 'Search tasks...', '搜索任务...'),
                  hintStyle: searchTextStyle?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            filterChip(
              label: '${_localized(context, 'All', '全部')} $total',
              selected: filter == _TaskStatusFilter.all,
              onSelected: () => onFilterChanged(_TaskStatusFilter.all),
            ),
            filterChip(
              label: '${_localized(context, 'Enabled', '已启用')} $enabled',
              selected: filter == _TaskStatusFilter.enabled,
              onSelected: () => onFilterChanged(_TaskStatusFilter.enabled),
            ),
            filterChip(
              label: '${_localized(context, 'Running', '运行中')} $running',
              selected: filter == _TaskStatusFilter.running,
              onSelected: () => onFilterChanged(_TaskStatusFilter.running),
            ),
            filterChip(
              label: '${_localized(context, 'Error', '异常')} $error',
              selected: filter == _TaskStatusFilter.error,
              onSelected: () => onFilterChanged(_TaskStatusFilter.error),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = compact
            ? constraints.maxWidth
            : constraints.maxWidth < 320
            ? constraints.maxWidth
            : 320.0;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: _localized(context, 'Search tasks...', '搜索任务...'),
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
                  label: Text('${_localized(context, 'All', '全部')} $total'),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.enabled,
                  label: Text(
                    '${_localized(context, 'Enabled', '已启用')} $enabled',
                  ),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.running,
                  label: Text(
                    '${_localized(context, 'Running', '运行中')} $running',
                  ),
                ),
                ButtonSegment(
                  value: _TaskStatusFilter.error,
                  label: Text('${_localized(context, 'Error', '异常')} $error'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ContentMeta extends StatelessWidget {
  final int visibleCount;

  const _ContentMeta({required this.visibleCount});

  @override
  Widget build(BuildContext context) {
    return Text(
      _localized(
        context,
        'Showing $visibleCount tasks, sorted by next run and name',
        '当前显示 $visibleCount 个任务，按下次执行时间和名称排序',
      ),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TaskCardWrap extends StatelessWidget {
  final List<ManagedTask> tasks;
  final List<Conversation> conversations;
  final bool compact;
  final String? selectedTaskId;
  final Set<String> busyTaskIds;
  final Set<String> togglingTaskIds;
  final ValueChanged<ManagedTask> onOpen;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskCardWrap({
    required this.tasks,
    required this.conversations,
    required this.compact,
    required this.selectedTaskId,
    required this.busyTaskIds,
    required this.togglingTaskIds,
    required this.onOpen,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = !compact && constraints.maxWidth >= 1260 ? 2 : 1;
        const gap = 14.0;
        final cardWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final task in tasks)
              SizedBox(
                width: cardWidth,
                child: _TaskCard(
                  task: task,
                  conversations: conversations,
                  selected: selectedTaskId == task.id,
                  isBusy: busyTaskIds.contains(task.id),
                  isToggleBusy: togglingTaskIds.contains(task.id),
                  onOpen: onOpen,
                  onToggle: onToggle,
                  onRun: onRun,
                  onRuns: onRuns,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  final ManagedTask task;
  final List<Conversation> conversations;
  final bool selected;
  final bool isBusy;
  final bool isToggleBusy;
  final ValueChanged<ManagedTask> onOpen;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskCard({
    required this.task,
    required this.conversations,
    required this.selected,
    required this.isBusy,
    required this.isToggleBusy,
    required this.onOpen,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme, task);
    final accentColor = _taskAccentColor(colorScheme, task);
    return Material(
      key: ValueKey('task_card_${task.id}'),
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => onOpen(task),
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
                colorScheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 16,
                bottom: 16,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final rightRail = constraints.maxWidth >= 980;
                    final icon = _TaskIcon(task: task, color: statusColor);
                    final main = _TaskCardMain(
                      task: task,
                      conversations: conversations,
                    );
                    final controls = _TaskControls(
                      key: ValueKey('task_card_controls_${task.id}'),
                      task: task,
                      vertical: rightRail,
                      isBusy: isBusy,
                      isToggleBusy: isToggleBusy,
                      onToggle: onToggle,
                      onRun: onRun,
                      onRuns: onRuns,
                    );

                    if (rightRail) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 160),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 18),
                            Expanded(child: main),
                            const SizedBox(width: 18),
                            SizedBox(width: 176, child: controls),
                          ],
                        ),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 18),
                            Expanded(child: main),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: controls,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskIcon extends StatelessWidget {
  final ManagedTask task;
  final Color color;

  const _TaskIcon({required this.task, required this.color});

  @override
  Widget build(BuildContext context) {
    final iconData = _taskIcon(task);
    return Container(
      key: ValueKey('task_card_icon_${task.id}'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(iconData, color: color, size: 26),
    );
  }
}

class _TaskCardMain extends StatelessWidget {
  final ManagedTask task;
  final List<Conversation> conversations;

  const _TaskCardMain({required this.task, required this.conversations});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(colorScheme, task);
    final delivery = validateTaskDeliveryTarget(
      deliver: task.deliver,
      accountId: task.accountId,
      conversations: conversations,
    );
    return Column(
      key: ValueKey('task_card_main_${task.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 9,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              task.name.isEmpty ? task.id : task.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            _StatusPill(label: _statusLabel(context, task), color: statusColor),
            if (!delivery.isValid) _TaskDeliveryWarningPill(delivery: delivery),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          task.prompt,
          key: ValueKey('task_card_desc_${task.id}'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.86),
            height: 1.42,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _TaskMetaLine(task: task),
      ],
    );
  }
}

class _TaskMetaLine extends StatelessWidget {
  final ManagedTask task;

  const _TaskMetaLine({required this.task});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (task.nextRunAt != null && task.nextRunAt!.isNotEmpty)
        '${_localized(context, 'Next', '下次')} ${task.nextRunAt}'
      else if (task.schedule.isNotEmpty)
        _taskScheduleDisplayText(context, task.schedule)
      else
        _localized(context, 'No schedule', '无定时计划'),
      if (task.lastRun != null)
        '${_localized(context, 'Last', '上次')}${_runStatusLabel(context, task.lastRun!.status)} ${_formatTaskRunTime(task.lastRun!.startedAt)}',
      if (_taskSkillsSupported(task.agent) && task.skills.isNotEmpty)
        '${_localized(context, 'Skills', '技能')}：${task.skills.take(3).join(', ')}',
    ];
    return Wrap(
      spacing: 11,
      runSpacing: 6,
      children: [
        for (final part in parts)
          Text(
            part,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _TaskControls extends StatelessWidget {
  final ManagedTask task;
  final bool vertical;
  final bool isBusy;
  final bool isToggleBusy;
  final void Function(ManagedTask task, bool enabled) onToggle;
  final ValueChanged<ManagedTask> onRun;
  final ValueChanged<ManagedTask> onRuns;

  const _TaskControls({
    super.key,
    required this.task,
    required this.vertical,
    required this.isBusy,
    required this.isToggleBusy,
    required this.onToggle,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final top = isBusy || isToggleBusy
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : SizedBox(
            width: 50,
            height: 30,
            child: Transform.scale(
              scale: 0.82,
              child: Switch(
                value: task.enabled,
                onChanged: (value) => onToggle(task, value),
              ),
            ),
          );

    final actions = [
      _TaskActionButton(
        icon: Icons.play_arrow,
        label: _localized(context, 'Run now', '立即执行'),
        onPressed: isBusy ? null : () => onRun(task),
      ),
      _TaskActionButton(
        icon: Icons.receipt_long_outlined,
        label: _localized(context, 'Run History', '执行记录'),
        onPressed: isBusy ? null : () => onRuns(task),
        secondary: true,
      ),
    ];

    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          top,
          const SizedBox(height: 10),
          for (final action in actions) ...[
            SizedBox(width: double.infinity, child: action),
            if (action != actions.last) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [top, ...actions],
    );
  }
}

class _TaskActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;

  const _TaskActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.secondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Text(label);
    if (secondary) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: child,
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: child,
    );
  }
}

class _TaskPageShell extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? action;
  final List<Widget> children;

  const _TaskPageShell({
    required this.title,
    required this.onBack,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TaskSubPageAppBar(title: title, onBack: onBack, action: action),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              final padding = compact
                  ? const EdgeInsets.fromLTRB(12, 14, 12, 24)
                  : const EdgeInsets.all(28);
              return SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TaskSubPageAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? action;

  const _TaskSubPageAppBar({
    required this.title,
    required this.onBack,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('task_page_app_bar'),
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideWidth = constraints.maxWidth < 560 ? 112.0 : 180.0;
          return Row(
            children: [
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const ValueKey('task_app_bar_back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: sideWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: action ?? const SizedBox.shrink(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskAppBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const _TaskAppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      key: const ValueKey('task_app_bar_action'),
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            )
          : Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

class _TaskDetailPage extends StatelessWidget {
  final ManagedTask task;
  final List<Conversation> conversations;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onRun;
  final VoidCallback onRuns;

  const _TaskDetailPage({
    required this.task,
    required this.conversations,
    required this.onBack,
    required this.onEdit,
    required this.onRun,
    required this.onRuns,
  });

  @override
  Widget build(BuildContext context) {
    final delivery = validateTaskDeliveryTarget(
      deliver: task.deliver,
      accountId: task.accountId,
      conversations: conversations,
    );
    return _TaskPageShell(
      title: _localized(context, 'Task Detail', '任务详情'),
      onBack: onBack,
      action: _TaskAppBarAction(
        icon: Icons.edit_outlined,
        label: _localized(context, 'Edit', '编辑'),
        onPressed: onEdit,
      ),
      children: [
        _DetailPanel(
          key: const ValueKey('task_detail_overview'),
          title: _localized(context, 'Basic Info', '基本信息'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!delivery.isValid) ...[
                _TaskDeliveryNotice(delivery: delivery),
                const SizedBox(height: 18),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 720;
                  final definitionRows = <(String, Object)>[
                    (
                      _localized(context, 'Name', '名称'),
                      task.name.isEmpty ? task.id : task.name,
                    ),
                    (_localized(context, 'Gateway', 'Gateway'), task.accountId),
                    (
                      _localized(context, 'Execution schedule', '执行计划'),
                      _taskScheduleDisplayText(context, task.schedule),
                    ),
                    if (_taskSkillsSupported(task.agent))
                      (
                        _localized(context, 'Skills', '技能'),
                        task.skills.isEmpty
                            ? _localized(context, 'Agent default', 'Agent 默认')
                            : task.skills.join(', '),
                      ),
                    (
                      _localized(context, 'Delivery conversation', '交付会话'),
                      _taskDeliveryDisplayText(context, delivery),
                    ),
                  ];
                  final definition = _RunsInfoSection(rows: definitionRows);
                  final recent = _RunsInfoSection(
                    rows: [
                      (
                        _localized(context, 'Status', '状态'),
                        _statusLabel(context, task),
                      ),
                      (
                        _localized(context, 'Next Run', '下次运行'),
                        _taskNextRunDisplayText(context, task),
                      ),
                    ],
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: definition),
                        const SizedBox(width: 18),
                        Expanded(child: recent),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [definition, const SizedBox(height: 16), recent],
                  );
                },
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onRun,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_localized(context, 'Run now', '立即执行')),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRuns,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: Text(_localized(context, 'Run History', '执行记录')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DetailPanel(
          key: const ValueKey('task_detail_prompt'),
          title: _localized(context, 'Task Prompt', '任务提示词'),
          child: _PromptBox(text: task.prompt),
        ),
      ],
    );
  }
}

class _TaskRunsPage extends StatelessWidget {
  final ManagedTask task;
  final TasksState state;
  final List<Conversation> conversations;
  final VoidCallback onBack;
  final ValueChanged<TaskRun> onOpenOutput;

  const _TaskRunsPage({
    required this.task,
    required this.state,
    required this.conversations,
    required this.onBack,
    required this.onOpenOutput,
  });

  @override
  Widget build(BuildContext context) {
    final delivery = validateTaskDeliveryTarget(
      deliver: task.deliver,
      accountId: task.accountId,
      conversations: conversations,
    );
    return _TaskPageShell(
      title: _localized(context, 'Run History', '执行记录'),
      onBack: onBack,
      children: [
        _DetailPanel(
          key: const ValueKey('task_runs_overview'),
          title: _localized(context, 'Basic Info', '基本信息'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final taskInfo = _RunsInfoSection(
                rows: [
                  (
                    _localized(context, 'Name', '名称'),
                    task.name.isEmpty ? task.id : task.name,
                  ),
                  (_localized(context, 'Gateway', 'Gateway'), task.accountId),
                  (
                    _localized(context, 'Delivery conversation', '交付会话'),
                    _taskDeliveryDisplayText(context, delivery),
                  ),
                  (
                    _localized(context, 'Execution schedule', '执行计划'),
                    _taskScheduleDisplayText(context, task.schedule),
                  ),
                ],
              );
              final runInfo = _RunsInfoSection(
                rows: [
                  (
                    _localized(context, 'Total Runs', '总次数'),
                    state.runs.length.toString(),
                  ),
                  (
                    _localized(context, 'Latest Success', '最近成功'),
                    _latestRunAt(
                      context,
                      state.runs,
                      (run) => _isRunSuccess(run.status),
                    ),
                  ),
                  (
                    _localized(context, 'Latest Failure', '最近失败'),
                    _latestRunAt(
                      context,
                      state.runs,
                      (run) => _isRunFailure(run.status),
                    ),
                  ),
                ],
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: taskInfo),
                    const SizedBox(width: 18),
                    Expanded(child: runInfo),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [taskInfo, const SizedBox(height: 16), runInfo],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _DetailPanel(
          key: const ValueKey('task_runs_list_panel'),
          title: _localized(context, 'Run History', '执行记录'),
          child: _RunsList(state: state, onOpenOutput: onOpenOutput),
        ),
      ],
    );
  }
}

class _RunsInfoSection extends StatelessWidget {
  final List<(String, Object)> rows;

  const _RunsInfoSection({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_KeyValueList(rows: rows)],
    );
  }
}

class _RunsList extends StatelessWidget {
  final TasksState state;
  final ValueChanged<TaskRun> onOpenOutput;

  const _RunsList({required this.state, required this.onOpenOutput});

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingRuns) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (state.runs.isEmpty) {
      return _StatePanel(
        icon: Icons.receipt_long_outlined,
        title: _localized(context, 'No runs yet', '暂无执行记录'),
        message: _localized(
          context,
          'Run this task to inspect execution output.',
          '执行任务后即可查看执行结果。',
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < state.runs.length; index++) ...[
          _RunCard(
            run: state.runs[index],
            onTap: () => onOpenOutput(state.runs[index]),
          ),
          if (index != state.runs.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _TaskRunOutputPage extends StatelessWidget {
  final ManagedTask task;
  final TaskRun run;
  final String? output;
  final List<Conversation> conversations;
  final VoidCallback onBack;

  const _TaskRunOutputPage({
    required this.task,
    required this.run,
    required this.output,
    required this.conversations,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = output == null || output!.isEmpty
        ? _localized(context, 'Loading output...', '正在加载结果...')
        : output!;
    final delivery = validateTaskDeliveryTarget(
      deliver: task.deliver,
      accountId: task.accountId,
      conversations: conversations,
    );
    return _TaskPageShell(
      title: _localized(context, 'Run Output', '执行结果'),
      onBack: onBack,
      children: [
        _DetailPanel(
          key: const ValueKey('task_output_info'),
          title: _localized(context, 'Run Metadata', '执行信息'),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final taskInfo = _RunsInfoSection(
                rows: [
                  (
                    _localized(context, 'Name', '名称'),
                    task.name.isEmpty ? task.id : task.name,
                  ),
                  (_localized(context, 'Run ID', 'Run ID'), run.id),
                  (_localized(context, 'Gateway', 'Gateway'), task.accountId),
                  (
                    _localized(context, 'Delivery conversation', '交付会话'),
                    _TaskDeliveryDisplayValue(delivery: delivery),
                  ),
                ],
              );
              final statusInfo = _RunsInfoSection(
                rows: [
                  (
                    _localized(context, 'Result', '结果'),
                    _runStatusLabel(context, run.status),
                  ),
                  (
                    _localized(context, 'Started', '开始时间'),
                    _formatTaskRunTime(run.startedAt),
                  ),
                  if (run.finishedAt != null && run.finishedAt!.isNotEmpty)
                    (
                      _localized(context, 'Finished', '结束时间'),
                      _formatTaskRunTime(run.finishedAt!),
                    ),
                ],
              );

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: taskInfo),
                    const SizedBox(width: 18),
                    Expanded(child: statusInfo),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [taskInfo, const SizedBox(height: 16), statusInfo],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _DetailPanel(
          key: const ValueKey('task_output_content'),
          title: _localized(context, 'Output Content', '输出内容'),
          trailing: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: body));
              showAppSnackBar(
                context,
                _localized(context, 'Output copied', '输出已复制'),
                duration: const Duration(seconds: 1),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.copy, size: 18),
            label: Text(_localized(context, 'Copy', '复制')),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 360),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: CopyableText(
                  body,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  const _DetailPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _TaskDeliveryNotice extends StatelessWidget {
  final TaskDeliveryValidation delivery;

  const _TaskDeliveryNotice({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('task_delivery_warning_notice'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localized(context, 'Delivery warning', '投递配置异常'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _taskDeliveryWarningText(context, delivery),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValueList extends StatelessWidget {
  final List<(String, Object)> rows;

  const _KeyValueList({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: CopyableText(
                    row.$1,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(child: _KeyValueValue(value: row.$2)),
              ],
            ),
          ),
      ],
    );
  }
}

class _KeyValueValue extends StatelessWidget {
  final Object value;

  const _KeyValueValue({required this.value});

  @override
  Widget build(BuildContext context) {
    final current = value;
    if (current is Widget) return current;
    return CopyableText(
      current.toString(),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }
}

class _TaskDeliveryDisplayValue extends StatelessWidget {
  final TaskDeliveryValidation delivery;

  const _TaskDeliveryDisplayValue({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final conversation = delivery.conversation;
    if (conversation == null) {
      return _KeyValueValue(value: _taskDeliveryDisplayText(context, delivery));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final title = _conversationTitle(conversation);
    final conversationId = delivery.conversationId;
    final valueStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    if (conversationId == null ||
        conversationId.isEmpty ||
        conversationId == title) {
      return CopyableText(title, style: valueStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CopyableText(title, style: valueStyle),
        const SizedBox(height: 3),
        CopyableText(
          conversationId,
          maxLines: 2,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _PromptBox extends StatelessWidget {
  final String text;

  const _PromptBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: CopyableText(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  final TaskRun run;
  final VoidCallback onTap;

  const _RunCard({required this.run, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _runColor(colorScheme, run.status);
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final details = _RunCardDetails(run: run, color: color);
              final action = OutlinedButton(
                onPressed: onTap,
                child: Text(_runOpenLabel(context, run.status)),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [details, const SizedBox(height: 12), action],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 14),
                  action,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RunCardDetails extends StatelessWidget {
  final TaskRun run;
  final Color color;

  const _RunCardDetails({required this.run, required this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _formatTaskRunTime(run.startedAt),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            _StatusPill(
              label: _runStatusLabel(context, run.status),
              color: color,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              run.id,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (run.finishedAt != null && run.finishedAt!.isNotEmpty)
              Text(
                '${_localized(context, 'Finished', '结束')} ${_formatTaskRunTime(run.finishedAt!)}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _runPreview(context, run),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.82),
            fontWeight: FontWeight.w600,
            height: 1.38,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 7),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TaskDeliveryWarningPill extends StatelessWidget {
  final TaskDeliveryValidation delivery;

  const _TaskDeliveryWarningPill({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Tooltip(
      message: _taskDeliveryWarningText(context, delivery),
      child: _StatusPill(
        label: _localized(context, 'Delivery warning', '投递异常'),
        color: color,
      ),
    );
  }
}

class _FieldHelper extends StatelessWidget {
  final String text;

  const _FieldHelper({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CreateTarget extends StatelessWidget {
  final String accountId;

  const _CreateTarget({required this.accountId});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text.rich(
        TextSpan(
          text: _localized(context, 'Create target: ', '创建目标：'),
          children: [
            TextSpan(
              text:
                  '${_localized(context, 'Current Gateway', '当前 Gateway')} · $accountId',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TaskSchedulePicker extends StatelessWidget {
  final String schedule;
  final ValueChanged<String> onChanged;

  const _TaskSchedulePicker({required this.schedule, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FormField<String>(
      initialValue: schedule,
      validator: (_) {
        final current = schedule.trim();
        if (current.isEmpty) return _localized(context, 'Required', '必填');
        if (!_isValidCronExpression(current)) {
          return _localized(context, 'Invalid cron expression', 'Cron 表达式不合法');
        }
        return null;
      },
      builder: (field) {
        final current = (field.value ?? schedule).trim();
        final display = current.isEmpty
            ? _localized(context, 'Set schedule', '设置计划')
            : _taskScheduleDisplayText(context, current);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localized(context, 'Execution schedule', '执行计划'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('task_schedule_picker'),
              onPressed: () async {
                final selected = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  constraints: const BoxConstraints(maxWidth: 680),
                  builder: (sheetContext) =>
                      _TaskScheduleSheet(initialCron: current),
                );
                if (selected == null) return;
                onChanged(selected);
                field.didChange(selected);
              },
              icon: const Icon(Icons.schedule_outlined),
              label: Row(
                children: [
                  Expanded(
                    child: Text(
                      display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(
                  color: field.hasError
                      ? colorScheme.error
                      : colorScheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 7, left: 12),
                child: Text(
                  field.errorText!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TaskScheduleSheet extends StatefulWidget {
  final String initialCron;

  const _TaskScheduleSheet({required this.initialCron});

  @override
  State<_TaskScheduleSheet> createState() => _TaskScheduleSheetState();
}

class _TaskScheduleSheetState extends State<_TaskScheduleSheet> {
  late _TaskScheduleMode _mode;
  late _TaskFrequencyUnit _frequencyUnit;
  late int _frequency;
  late int _hour;
  late int _minute;
  late int _monthDay;
  late Set<int> _weekdays;
  late final TextEditingController _advancedController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final initial = _TaskScheduleDraft.fromCron(widget.initialCron);
    _mode = initial.mode;
    _frequencyUnit = initial.frequencyUnit;
    _frequency = initial.frequency;
    _hour = initial.hour;
    _minute = initial.minute;
    _monthDay = initial.monthDay;
    _weekdays = {...initial.weekdays};
    _advancedController = TextEditingController(text: initial.advancedCron);
    _advancedController.addListener(() {
      if (_mode == _TaskScheduleMode.advanced) setState(() {});
    });
  }

  @override
  void dispose() {
    _advancedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cron = _currentCron();
    final valid = _isValidCronExpression(cron);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _localized(context, 'Set schedule', '设置计划'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_TaskScheduleMode>(
                  segments: [
                    ButtonSegment(
                      value: _TaskScheduleMode.daily,
                      label: Text(_localized(context, 'Daily', '每天')),
                    ),
                    ButtonSegment(
                      value: _TaskScheduleMode.weekly,
                      label: Text(_localized(context, 'Weekly', '每周')),
                    ),
                    ButtonSegment(
                      value: _TaskScheduleMode.monthly,
                      label: Text(_localized(context, 'Monthly', '每月')),
                    ),
                    ButtonSegment(
                      value: _TaskScheduleMode.frequent,
                      label: Text(_localized(context, 'Frequent', '高频')),
                    ),
                    ButtonSegment(
                      value: _TaskScheduleMode.advanced,
                      label: Text(_localized(context, 'Advanced', '高级')),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    setState(() {
                      _mode = selection.single;
                      _errorText = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),
              _modeBody(context),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      valid
                          ? _taskScheduleDisplayText(context, cron)
                          : _localized(context, 'Invalid schedule', '计划不合法'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cron.isEmpty ? _localized(context, 'Empty', '空') : cron,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () {
                      final current = _currentCron();
                      if (!_isValidCronExpression(current)) {
                        setState(() {
                          _errorText = _localized(
                            context,
                            'Invalid cron expression',
                            'Cron 表达式不合法',
                          );
                        });
                        return;
                      }
                      Navigator.of(context).pop(current);
                    },
                    child: Text(_localized(context, 'Apply', '应用')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeBody(BuildContext context) {
    return switch (_mode) {
      _TaskScheduleMode.daily => _timeSelectors(context),
      _TaskScheduleMode.weekly => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final weekday in [1, 2, 3, 4, 5, 6, 0])
                FilterChip(
                  key: ValueKey('task_schedule_weekday_$weekday'),
                  label: Text(_weekdayShort(context, weekday)),
                  selected: _weekdays.contains(weekday),
                  showCheckmark: false,
                  onSelected: (_) {
                    if (_weekdays.contains(weekday) && _weekdays.length == 1) {
                      return;
                    }
                    setState(() {
                      if (_weekdays.contains(weekday)) {
                        _weekdays.remove(weekday);
                      } else {
                        _weekdays.add(weekday);
                      }
                      _errorText = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _timeSelectors(context),
        ],
      ),
      _TaskScheduleMode.monthly => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            key: const ValueKey('task_schedule_month_day'),
            initialValue: _monthDay,
            decoration: InputDecoration(
              labelText: _localized(context, 'Day', '日期'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var day = 1; day <= 31; day++)
                DropdownMenuItem(
                  value: day,
                  child: Text(_localized(context, 'Day $day', '$day 日')),
                ),
            ],
            onChanged: (value) => setState(() => _monthDay = value ?? 1),
          ),
          const SizedBox(height: 14),
          _timeSelectors(context),
        ],
      ),
      _TaskScheduleMode.frequent => _frequencySelectors(context),
      _TaskScheduleMode.advanced => TextField(
        key: const ValueKey('task_schedule_advanced_input'),
        controller: _advancedController,
        decoration: InputDecoration(
          labelText: _localized(context, 'Cron', 'Cron'),
          hintText: '0 9 * * *',
          border: const OutlineInputBorder(),
        ),
      ),
    };
  }

  Widget _timeSelectors(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: const ValueKey('task_schedule_hour'),
            initialValue: _hour,
            decoration: InputDecoration(
              labelText: _localized(context, 'Hour', '小时'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var hour = 0; hour < 24; hour++)
                DropdownMenuItem(value: hour, child: Text(_two(hour))),
            ],
            onChanged: (value) => setState(() => _hour = value ?? 9),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int>(
            key: const ValueKey('task_schedule_minute'),
            initialValue: _minute,
            decoration: InputDecoration(
              labelText: _localized(context, 'Minute', '分钟'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var minute = 0; minute < 60; minute++)
                DropdownMenuItem(value: minute, child: Text(_two(minute))),
            ],
            onChanged: (value) => setState(() => _minute = value ?? 0),
          ),
        ),
      ],
    );
  }

  Widget _frequencySelectors(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FrequencyOption(
          key: const ValueKey('task_schedule_frequency_minute'),
          selected: _frequencyUnit == _TaskFrequencyUnit.minute,
          unitLabel: _localized(context, 'minutes', '分钟'),
          value: _frequencyUnit == _TaskFrequencyUnit.minute ? _frequency : 5,
          min: 1,
          max: 59,
          onSelected: (value) {
            setState(() {
              _frequencyUnit = _TaskFrequencyUnit.minute;
              _frequency = value;
              _errorText = null;
            });
          },
        ),
        const SizedBox(height: 10),
        _FrequencyOption(
          key: const ValueKey('task_schedule_frequency_hour'),
          selected: _frequencyUnit == _TaskFrequencyUnit.hour,
          unitLabel: _localized(context, 'hours', '小时'),
          value: _frequencyUnit == _TaskFrequencyUnit.hour ? _frequency : 1,
          min: 1,
          max: 23,
          onSelected: (value) {
            setState(() {
              _frequencyUnit = _TaskFrequencyUnit.hour;
              _frequency = value;
              _errorText = null;
            });
          },
        ),
      ],
    );
  }

  String _currentCron() {
    return switch (_mode) {
      _TaskScheduleMode.daily => '$_minute $_hour * * *',
      _TaskScheduleMode.weekly =>
        '$_minute $_hour * * ${_weekdaysCronValue(_weekdays)}',
      _TaskScheduleMode.monthly => '$_minute $_hour $_monthDay * *',
      _TaskScheduleMode.frequent =>
        _frequencyUnit == _TaskFrequencyUnit.minute
            ? '*/$_frequency * * * *'
            : '0 */$_frequency * * *',
      _TaskScheduleMode.advanced => _advancedController.text.trim(),
    };
  }
}

class _FrequencyOption extends StatelessWidget {
  final bool selected;
  final String unitLabel;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onSelected;

  const _FrequencyOption({
    super.key,
    required this.selected,
    required this.unitLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onSelected(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Text(
              _localized(context, 'Every', '每'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 98,
              child: DropdownButtonFormField<int>(
                initialValue: value.clamp(min, max).toInt(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (var item = min; item <= max; item++)
                    DropdownMenuItem(value: item, child: Text(item.toString())),
                ],
                onChanged: (next) => onSelected(next ?? value),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              unitLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskScheduleDraft {
  final _TaskScheduleMode mode;
  final _TaskFrequencyUnit frequencyUnit;
  final int frequency;
  final int hour;
  final int minute;
  final int monthDay;
  final Set<int> weekdays;
  final String advancedCron;

  const _TaskScheduleDraft({
    required this.mode,
    required this.frequencyUnit,
    required this.frequency,
    required this.hour,
    required this.minute,
    required this.monthDay,
    required this.weekdays,
    required this.advancedCron,
  });

  factory _TaskScheduleDraft.fromCron(String value) {
    final cron = value.trim();
    final parts = cron.split(RegExp(r'\s+'));
    if (parts.length == 5) {
      final minute = parts[0];
      final hour = parts[1];
      final day = parts[2];
      final month = parts[3];
      final weekday = parts[4];

      final minuteInterval = RegExp(r'^\*/(\d+)$').firstMatch(minute);
      if (minuteInterval != null &&
          hour == '*' &&
          day == '*' &&
          month == '*' &&
          weekday == '*') {
        return _TaskScheduleDraft.defaults(
          mode: _TaskScheduleMode.frequent,
          frequencyUnit: _TaskFrequencyUnit.minute,
          frequency: int.tryParse(minuteInterval.group(1)!) ?? 5,
          advancedCron: cron,
        );
      }

      final hourInterval = RegExp(r'^\*/(\d+)$').firstMatch(hour);
      if ((minute == '0') &&
          hourInterval != null &&
          day == '*' &&
          month == '*' &&
          weekday == '*') {
        return _TaskScheduleDraft.defaults(
          mode: _TaskScheduleMode.frequent,
          frequencyUnit: _TaskFrequencyUnit.hour,
          frequency: int.tryParse(hourInterval.group(1)!) ?? 1,
          advancedCron: cron,
        );
      }

      final parsedMinute = int.tryParse(minute);
      final parsedHour = int.tryParse(hour);
      if (parsedMinute != null && parsedHour != null) {
        if (day == '*' && month == '*' && weekday == '*') {
          return _TaskScheduleDraft.defaults(
            mode: _TaskScheduleMode.daily,
            hour: parsedHour,
            minute: parsedMinute,
            advancedCron: cron,
          );
        }
        if (day == '*' && month == '*' && weekday != '*') {
          return _TaskScheduleDraft.defaults(
            mode: _TaskScheduleMode.weekly,
            hour: parsedHour,
            minute: parsedMinute,
            weekdays: _parseWeekdays(weekday),
            advancedCron: cron,
          );
        }
        final parsedDay = int.tryParse(day);
        if (parsedDay != null && month == '*' && weekday == '*') {
          return _TaskScheduleDraft.defaults(
            mode: _TaskScheduleMode.monthly,
            hour: parsedHour,
            minute: parsedMinute,
            monthDay: parsedDay,
            advancedCron: cron,
          );
        }
      }
    }

    return _TaskScheduleDraft.defaults(
      mode: _TaskScheduleMode.daily,
      advancedCron: cron,
    );
  }

  factory _TaskScheduleDraft.defaults({
    required _TaskScheduleMode mode,
    _TaskFrequencyUnit frequencyUnit = _TaskFrequencyUnit.minute,
    int frequency = 5,
    int hour = 9,
    int minute = 0,
    int monthDay = 1,
    Set<int>? weekdays,
    String advancedCron = '',
  }) {
    return _TaskScheduleDraft(
      mode: mode,
      frequencyUnit: frequencyUnit,
      frequency: frequency,
      hour: hour.clamp(0, 23).toInt(),
      minute: minute.clamp(0, 59).toInt(),
      monthDay: monthDay.clamp(1, 31).toInt(),
      weekdays: weekdays == null || weekdays.isEmpty ? {1} : weekdays,
      advancedCron: advancedCron,
    );
  }
}

class _ConversationDeliveryPicker extends StatelessWidget {
  final String accountId;
  final String? deliver;
  final List<Conversation> conversations;
  final ValueChanged<String> onChanged;

  const _ConversationDeliveryPicker({
    required this.accountId,
    required this.deliver,
    required this.conversations,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accountConversations = taskDeliveryConversationsForAccount(
      accountId: accountId,
      conversations: conversations,
    );
    final delivery = validateTaskDeliveryTarget(
      deliver: deliver,
      accountId: accountId,
      conversations: conversations,
    );
    final selected = delivery.conversation;
    final label = selected == null
        ? _localized(context, 'Choose delivery conversation', '选择交付会话')
        : _conversationTitle(selected);
    final colorScheme = Theme.of(context).colorScheme;

    return FormField<String>(
      initialValue: deliver,
      validator: (_) =>
          validateTaskDeliveryTarget(
            deliver: deliver,
            accountId: accountId,
            conversations: conversations,
          ).isValid
          ? null
          : _localized(context, 'Required', '必填'),
      builder: (field) {
        final hasError = field.hasError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _localized(context, 'Delivery conversation', '交付会话'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('task_delivery_picker'),
              onPressed: accountConversations.isEmpty
                  ? null
                  : () async {
                      final selected = await showModalBottomSheet<Conversation>(
                        context: context,
                        showDragHandle: true,
                        builder: (sheetContext) => _ConversationDeliverySheet(
                          conversations: accountConversations,
                          selectedConversationId: delivery.conversationId,
                        ),
                      );
                      if (selected == null) return;
                      final value = taskConversationDeliveryValue(
                        selected.conversationId,
                      );
                      onChanged(value);
                      field.didChange(value);
                    },
              icon: const Icon(Icons.chat_bubble_outline),
              label: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 18),
                ],
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 13,
                ),
                minimumSize: const Size.fromHeight(52),
                side: BorderSide(
                  color: hasError ? colorScheme.error : colorScheme.outline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 7, left: 12),
                child: Text(
                  field.errorText!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConversationDeliverySheet extends StatelessWidget {
  final List<Conversation> conversations;
  final String? selectedConversationId;

  const _ConversationDeliverySheet({
    required this.conversations,
    required this.selectedConversationId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _localized(context, 'Choose delivery conversation', '选择交付会话'),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final conversation in conversations)
            ListTile(
              key: ValueKey(
                'task_delivery_conversation_${conversation.conversationId}',
              ),
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(_conversationTitle(conversation)),
              trailing: conversation.conversationId == selectedConversationId
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(conversation),
            ),
          if (conversations.isEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(
                _localized(
                  context,
                  'No conversations under this Gateway',
                  '当前 Gateway 下暂无会话',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TaskEditPage extends StatefulWidget {
  final String accountId;
  final String gatewayType;
  final ManagedTask? initial;
  final List<Conversation> conversations;
  final bool isSaving;
  final ValueChanged<TaskDraft> onSave;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;

  const _TaskEditPage({
    required this.accountId,
    required this.gatewayType,
    required this.initial,
    required this.conversations,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  State<_TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<_TaskEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  late final TextEditingController _skillsController;
  String? _selectedDeliver;
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
    final delivery = validateTaskDeliveryTarget(
      deliver: initial?.deliver,
      accountId: widget.accountId,
      conversations: widget.conversations,
    );
    _selectedDeliver = delivery.isValid ? initial?.deliver?.trim() : null;
    _enabled = initial?.enabled ?? true;
  }

  @override
  void didUpdateWidget(covariant _TaskEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initialDeliver = widget.initial?.deliver?.trim();
    if (_selectedDeliver != null ||
        initialDeliver == null ||
        initialDeliver.isEmpty) {
      return;
    }
    final delivery = validateTaskDeliveryTarget(
      deliver: initialDeliver,
      accountId: widget.accountId,
      conversations: widget.conversations,
    );
    if (delivery.isValid) {
      setState(() => _selectedDeliver = initialDeliver);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    _skillsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final supportsSkills = _taskSkillsSupported(widget.gatewayType);
    final isEditing = widget.initial != null;
    final title = widget.initial == null
        ? _localized(context, 'New Task', '新建任务')
        : _localized(context, 'Edit Task', '编辑任务');
    return _TaskPageShell(
      title: title,
      onBack: widget.onCancel,
      action: _TaskAppBarAction(
        icon: widget.initial == null ? Icons.add : Icons.save_outlined,
        label: widget.initial == null
            ? _localized(context, 'Create', '创建')
            : _localized(context, 'Save', '保存'),
        onPressed: _submit,
        busy: widget.isSaving,
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DetailPanel(
                key: const ValueKey('task_edit_basic_info'),
                title: _localized(context, 'Basic Info', '基础信息'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _localized(context, 'Name', '名称'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      key: const ValueKey('task_name_field'),
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _FieldHelper(
                      text: widget.initial == null
                          ? _localized(
                              context,
                              'Required. Used in task lists and run history.',
                              '必填。用于任务列表和执行记录展示。',
                            )
                          : _localized(
                              context,
                              'Used in task lists and detail titles.',
                              '用于任务列表和详情页标题。',
                            ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final schedulePicker = _TaskSchedulePicker(
                          schedule: _scheduleController.text,
                          onChanged: (value) =>
                              setState(() => _scheduleController.text = value),
                        );
                        final deliveryPicker = _ConversationDeliveryPicker(
                          accountId: widget.accountId,
                          deliver: _selectedDeliver,
                          conversations: widget.conversations,
                          onChanged: (value) =>
                              setState(() => _selectedDeliver = value),
                        );
                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              schedulePicker,
                              const SizedBox(height: 12),
                              deliveryPicker,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: schedulePicker),
                            const SizedBox(width: 12),
                            Expanded(child: deliveryPicker),
                          ],
                        );
                      },
                    ),
                    if (supportsSkills) ...[
                      const SizedBox(height: 12),
                      Text(
                        _localized(context, 'Skills', '技能'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: const ValueKey('task_skills_field'),
                        controller: _skillsController,
                        decoration: InputDecoration(
                          hintText: _localized(context, 'Skills', '技能'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      _FieldHelper(
                        text: _localized(
                          context,
                          'Optional. Comma separated; empty means the agent decides.',
                          '可选。逗号分隔；留空表示由 Agent 自行选择。',
                        ),
                      ),
                    ],
                    if (widget.initial == null) ...[
                      const SizedBox(height: 12),
                      _CreateTarget(accountId: widget.accountId),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DetailPanel(
                key: const ValueKey('task_edit_prompt'),
                title: _localized(context, 'Task Prompt', '任务提示词'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isEditing) ...[
                      Text(
                        _localized(
                          context,
                          'Write the goal, inputs, output format, and constraints. You can review it after creation.',
                          '写清楚任务目标、输入来源、输出格式和约束。创建后可在详情页立即查看。',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      key: const ValueKey('task_prompt_field'),
                      controller: _promptController,
                      minLines: 10,
                      maxLines: 16,
                      decoration: InputDecoration(
                        labelText: isEditing
                            ? null
                            : _localized(context, 'Prompt Content', '提示词内容'),
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? _localized(context, 'Required', '必填')
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.initial != null && widget.onDelete != null) ...[
          const SizedBox(height: 16),
          _DetailPanel(
            key: const ValueKey('task_edit_danger_zone'),
            title: _localized(context, 'Danger Zone', '危险操作'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _localized(
                    context,
                    'Deleting this task removes its definition and schedule. This action cannot be undone.',
                    '删除任务后，任务定义和执行计划会被移除，此操作不可撤销。',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.isSaving ? null : widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(_localized(context, 'Delete Task', '删除任务')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final skills = _taskSkillsSupported(widget.gatewayType)
        ? _skillsController.text
              .split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    widget.onSave(
      TaskDraft(
        accountId: widget.accountId,
        name: _nameController.text,
        schedule: _scheduleController.text,
        prompt: _promptController.text,
        enabled: _enabled,
        skills: skills,
        deliver: _selectedDeliver,
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
    return EmptyStatePanel(icon: icon, title: title, message: message);
  }
}

Color _statusColor(ColorScheme colorScheme, ManagedTask task) {
  if (!task.enabled) return colorScheme.outline;
  if (_isTaskError(task)) return colorScheme.error;
  if (task.status == 'paused' || task.status == 'disabled') {
    return colorScheme.outline;
  }
  if (_isTaskRunning(task)) return colorScheme.tertiary;
  return colorScheme.primary;
}

Color _taskAccentColor(ColorScheme colorScheme, ManagedTask task) {
  if (_isTaskError(task)) return colorScheme.error;
  if (_isTaskRunning(task)) return colorScheme.tertiary;
  if (!task.enabled || task.status == 'paused' || task.status == 'disabled') {
    return colorScheme.outline;
  }
  return colorScheme.primary;
}

IconData _taskIcon(ManagedTask task) {
  if (_isTaskError(task)) return Icons.priority_high;
  if (_isTaskRunning(task)) return Icons.play_arrow;
  if (!task.enabled || task.status == 'paused' || task.status == 'disabled') {
    return Icons.pause;
  }
  return Icons.task_alt;
}

bool _isTaskRunning(ManagedTask task) {
  return task.status == 'running' || task.lastRun?.status == 'running';
}

bool _isTaskError(ManagedTask task) {
  return task.status == 'error' || task.lastRun?.status == 'failed';
}

bool _taskSkillsSupported(String gatewayType) {
  return gatewayType.trim().toLowerCase() == 'hermes';
}

Color _runColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'failed' => colorScheme.error,
    'error' => colorScheme.error,
    'cancelled' => colorScheme.outline,
    'running' => colorScheme.tertiary,
    _ => colorScheme.primary,
  };
}

bool _isRunSuccess(String status) {
  return status == 'success' || status == 'succeeded' || status == 'completed';
}

bool _isRunFailure(String status) {
  return status == 'failed' || status == 'error';
}

String _latestRunAt(
  BuildContext context,
  List<TaskRun> runs,
  bool Function(TaskRun run) test,
) {
  for (final run in runs) {
    if (test(run)) return _formatTaskRunTime(run.startedAt);
  }
  return _localized(context, 'None', '暂无');
}

String _taskNextRunDisplayText(BuildContext context, ManagedTask task) {
  final provided = task.nextRunAt?.trim();
  if (provided != null && provided.isNotEmpty) {
    return _formatTaskRunTime(provided);
  }
  if (!task.enabled || task.status == 'paused' || task.status == 'disabled') {
    return _localized(context, 'Not scheduled', '未计划');
  }
  final nextRun = _nextRunFromCron(task.schedule, DateTime.now());
  if (nextRun == null) return _localized(context, 'Not scheduled', '未计划');
  return _formatDateTime(nextRun);
}

DateTime? _nextRunFromCron(String schedule, DateTime now) {
  final parts = schedule.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return null;

  final minutes = _parseCronValues(parts[0], 0, 59);
  final hours = _parseCronValues(parts[1], 0, 23);
  final days = _parseCronValues(parts[2], 1, 31);
  final months = _parseCronValues(parts[3], 1, 12);
  final weekdays = _parseCronValues(parts[4], 0, 7, normalizeSunday: true);
  if (minutes == null ||
      hours == null ||
      days == null ||
      months == null ||
      weekdays == null) {
    return null;
  }

  final dayRestricted = parts[2] != '*';
  final weekdayRestricted = parts[4] != '*';
  var candidate = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
  ).add(const Duration(minutes: 1));
  final end = candidate.add(const Duration(days: 366));

  while (!candidate.isAfter(end)) {
    final weekday = candidate.weekday == DateTime.sunday
        ? 0
        : candidate.weekday;
    final dayMatches = days.contains(candidate.day);
    final weekdayMatches = weekdays.contains(weekday);
    final dateMatches = dayRestricted && weekdayRestricted
        ? dayMatches || weekdayMatches
        : dayMatches && weekdayMatches;

    if (minutes.contains(candidate.minute) &&
        hours.contains(candidate.hour) &&
        months.contains(candidate.month) &&
        dateMatches) {
      return candidate;
    }
    candidate = candidate.add(const Duration(minutes: 1));
  }
  return null;
}

Set<int>? _parseCronValues(
  String field,
  int min,
  int max, {
  bool normalizeSunday = false,
}) {
  final values = <int>{};
  for (final token in field.split(',')) {
    final parsed = _parseCronTokenValues(token, min, max);
    if (parsed == null) return null;
    values.addAll(
      normalizeSunday ? parsed.map((value) => value == 7 ? 0 : value) : parsed,
    );
  }
  return values;
}

Set<int>? _parseCronTokenValues(String token, int min, int max) {
  final stepParts = token.split('/');
  if (stepParts.length > 2) return null;
  final step = stepParts.length == 2 ? int.tryParse(stepParts[1]) : 1;
  if (step == null || step < 1) return null;

  final base = stepParts[0];
  final startEnd = _cronTokenRange(base, min, max);
  if (startEnd == null) return null;
  final (start, end) = startEnd;
  final values = <int>{};
  for (var value = start; value <= end; value += step) {
    values.add(value);
  }
  return values;
}

(int, int)? _cronTokenRange(String token, int min, int max) {
  if (token == '*') return (min, max);
  if (token.contains('-')) {
    final range = token.split('-');
    if (range.length != 2) return null;
    final start = int.tryParse(range[0]);
    final end = int.tryParse(range[1]);
    if (start == null ||
        end == null ||
        start < min ||
        end > max ||
        start > end) {
      return null;
    }
    return (start, end);
  }
  final value = int.tryParse(token);
  if (value == null || value < min || value > max) return null;
  return (value, value);
}

String _formatTaskRunTime(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return value;

  final parsed = DateTime.tryParse(raw);
  if (parsed != null) return _formatDateTime(parsed.toLocal());

  final runIdMatch = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})_(\d{2})-(\d{2})-(\d{2})$',
  ).firstMatch(raw);
  if (runIdMatch != null) {
    return '${runIdMatch.group(1)}-${runIdMatch.group(2)}-${runIdMatch.group(3)} '
        '${runIdMatch.group(4)}:${runIdMatch.group(5)}:${runIdMatch.group(6)}';
  }

  return value;
}

String _formatDateTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

List<int> _orderedWeekdays(Set<int> weekdays) {
  return [
    1,
    2,
    3,
    4,
    5,
    6,
    0,
  ].where((weekday) => weekdays.contains(weekday)).toList();
}

bool _isWorkdayWeekdays(Set<int> weekdays) {
  return weekdays.length == 5 && const {1, 2, 3, 4, 5}.every(weekdays.contains);
}

String _weekdaysCronValue(Set<int> weekdays) {
  return _isWorkdayWeekdays(weekdays)
      ? '1-5'
      : _orderedWeekdays(weekdays).join(',');
}

Set<int> _parseWeekdays(String value) {
  final result = <int>{};
  for (final part in value.split(',')) {
    if (part.contains('-')) {
      final range = part.split('-');
      if (range.length != 2) continue;
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null || start > end) continue;
      for (var day = start; day <= end; day++) {
        if (day >= 0 && day <= 7) result.add(day == 7 ? 0 : day);
      }
      continue;
    }
    final day = int.tryParse(part);
    if (day != null && day >= 0 && day <= 7) result.add(day == 7 ? 0 : day);
  }
  return result.isEmpty ? {1} : result;
}

String _weekdayShort(BuildContext context, int weekday) {
  final zh = switch (weekday) {
    0 => '日',
    1 => '一',
    2 => '二',
    3 => '三',
    4 => '四',
    5 => '五',
    6 => '六',
    _ => '一',
  };
  final en = switch (weekday) {
    0 => 'Sun',
    1 => 'Mon',
    2 => 'Tue',
    3 => 'Wed',
    4 => 'Thu',
    5 => 'Fri',
    6 => 'Sat',
    _ => 'Mon',
  };
  return _localized(context, en, zh);
}

String _weekdayFull(BuildContext context, int weekday) {
  final zh = switch (weekday) {
    0 => '周日',
    1 => '周一',
    2 => '周二',
    3 => '周三',
    4 => '周四',
    5 => '周五',
    6 => '周六',
    _ => '周一',
  };
  final en = switch (weekday) {
    0 => 'Sunday',
    1 => 'Monday',
    2 => 'Tuesday',
    3 => 'Wednesday',
    4 => 'Thursday',
    5 => 'Friday',
    6 => 'Saturday',
    _ => 'Monday',
  };
  return _localized(context, en, zh);
}

String _taskScheduleDisplayText(BuildContext context, String schedule) {
  final cron = schedule.trim();
  final parts = cron.split(RegExp(r'\s+'));
  if (parts.length != 5) return cron;
  final minute = parts[0];
  final hour = parts[1];
  final day = parts[2];
  final month = parts[3];
  final weekday = parts[4];

  final minuteInterval = RegExp(r'^\*/(\d+)$').firstMatch(minute);
  if (minuteInterval != null &&
      hour == '*' &&
      day == '*' &&
      month == '*' &&
      weekday == '*') {
    final value = minuteInterval.group(1)!;
    return _localized(context, 'Every $value minutes', '每 $value 分钟');
  }

  final hourInterval = RegExp(r'^\*/(\d+)$').firstMatch(hour);
  if (minute == '0' &&
      hourInterval != null &&
      day == '*' &&
      month == '*' &&
      weekday == '*') {
    final value = hourInterval.group(1)!;
    return _localized(context, 'Every $value hours', '每 $value 小时');
  }

  final parsedMinute = int.tryParse(minute);
  final parsedHour = int.tryParse(hour);
  if (parsedMinute == null || parsedHour == null) return cron;
  final time = '${_two(parsedHour)}:${_two(parsedMinute)}';
  if (day == '*' && month == '*' && weekday == '*') {
    return _localized(context, 'Daily $time', '每天 $time');
  }
  if (day == '*' && month == '*' && weekday != '*') {
    final weekdays = _parseWeekdays(weekday);
    if (_isWorkdayWeekdays(weekdays)) {
      return _localized(context, 'Weekdays $time', '工作日 $time');
    }
    final days = _orderedWeekdays(weekdays)
        .map((item) => _weekdayFull(context, item))
        .join(_localized(context, ', ', '、'));
    return _localized(context, 'Weekly $days $time', '每$days $time');
  }
  final parsedDay = int.tryParse(day);
  if (parsedDay != null && month == '*' && weekday == '*') {
    return _localized(
      context,
      'Monthly day $parsedDay $time',
      '每月 $parsedDay 日 $time',
    );
  }
  return _localized(context, 'Advanced cron', '高级 Cron');
}

bool _isValidCronExpression(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return false;
  return _isValidCronField(parts[0], 0, 59) &&
      _isValidCronField(parts[1], 0, 23) &&
      _isValidCronField(parts[2], 1, 31) &&
      _isValidCronField(parts[3], 1, 12) &&
      _isValidCronField(parts[4], 0, 7);
}

bool _isValidCronField(String field, int min, int max) {
  if (field.isEmpty) return false;
  return field.split(',').every((token) => _isValidCronToken(token, min, max));
}

bool _isValidCronToken(String token, int min, int max) {
  final stepParts = token.split('/');
  if (stepParts.length > 2) return false;
  final base = stepParts[0];
  if (stepParts.length == 2 && !_isNumberInRange(stepParts[1], 1, 999)) {
    return false;
  }
  if (base == '*') return true;
  if (base.contains('-')) {
    final range = base.split('-');
    if (range.length != 2) return false;
    if (!_isNumberInRange(range[0], min, max) ||
        !_isNumberInRange(range[1], min, max)) {
      return false;
    }
    return int.parse(range[0]) <= int.parse(range[1]);
  }
  return stepParts.length == 1 && _isNumberInRange(base, min, max);
}

bool _isNumberInRange(String value, int min, int max) {
  final number = int.tryParse(value);
  return number != null && number >= min && number <= max;
}

String _runPreview(BuildContext context, TaskRun run) {
  if (run.outputPreview != null && run.outputPreview!.isNotEmpty) {
    return run.outputPreview!;
  }
  if (run.error != null && run.error!.isNotEmpty) return run.error!;
  if (run.status == 'running') {
    return _localized(
      context,
      'The task is still running. Output will refresh after the gateway returns.',
      '任务仍在执行，结果输出会在 Gateway 返回后自动刷新。',
    );
  }
  return _localized(context, 'No output preview', '暂无输出摘要');
}

String _runOpenLabel(BuildContext context, String status) {
  if (status == 'running') return _localized(context, 'View Status', '查看状态');
  if (_isRunFailure(status)) return _localized(context, 'View Error', '查看错误');
  return _localized(context, 'View Result', '查看结果');
}

String _statusLabel(BuildContext context, ManagedTask task) {
  if (!task.enabled) return _localized(context, 'Paused', '已暂停');
  return switch (task.status) {
    'error' => _localized(context, 'Error', '异常'),
    'running' => _localized(context, 'Running', '运行中'),
    'paused' || 'disabled' => _localized(context, 'Paused', '已暂停'),
    _ => switch (task.lastRun?.status) {
      'running' => _localized(context, 'Running', '运行中'),
      'failed' => _localized(context, 'Error', '异常'),
      _ => _localized(context, 'Active', '已启用'),
    },
  };
}

String _taskDeliveryWarningText(
  BuildContext context,
  TaskDeliveryValidation delivery,
) {
  final raw = delivery.rawTarget;
  return switch (delivery.reason) {
    TaskDeliveryInvalidReason.empty => _localized(
      context,
      'Delivery conversation is required. Choose a conversation in the current Gateway.',
      '必须选择交付会话。请从当前 Gateway 的会话中选择一个。',
    ),
    TaskDeliveryInvalidReason.userTarget => _localized(
      context,
      'user:* is not a valid task delivery target. Choose a conversation target.',
      'user:* 不是有效的任务投递目标。请选择 conversation 会话目标。',
    ),
    TaskDeliveryInvalidReason.invalidConversationId => _localized(
      context,
      'Delivery must use conversation:<uuid>.',
      '投递目标必须使用 conversation:<uuid>。',
    ),
    TaskDeliveryInvalidReason.missingConversation => _localized(
      context,
      'The conversation does not exist under the current Gateway.',
      '该会话不属于当前 Gateway，或本地会话列表中不存在。',
    ),
    TaskDeliveryInvalidReason.unsupportedTarget => _localized(
      context,
      raw == null
          ? 'Unsupported delivery target.'
          : 'Unsupported delivery target: $raw',
      raw == null ? '不支持的投递目标。' : '不支持的投递目标：$raw',
    ),
    TaskDeliveryInvalidReason.none => '',
  };
}

String _conversationTitle(Conversation conversation) {
  final name = conversation.name?.trim();
  return name == null || name.isEmpty ? conversation.conversationId : name;
}

String _taskDeliveryDisplayText(
  BuildContext context,
  TaskDeliveryValidation delivery, {
  bool includeId = false,
}) {
  final conversation = delivery.conversation;
  if (conversation != null) {
    final title = _conversationTitle(conversation);
    final conversationId = delivery.conversationId;
    if (includeId &&
        conversationId != null &&
        conversationId.isNotEmpty &&
        title != conversationId) {
      return '$title ($conversationId)';
    }
    return title;
  }
  if (delivery.isValid && delivery.conversationId != null) {
    return delivery.conversationId!;
  }
  return delivery.rawTarget ?? _localized(context, 'Not configured', '未配置');
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
