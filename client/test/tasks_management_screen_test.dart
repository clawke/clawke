import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/data/repositories/task_cache_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/screens/tasks_management_screen.dart';
import 'package:client/services/tasks_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/pump_helpers.dart';

const _hermesGateway = GatewayInfo(
  gatewayId: 'hermes',
  displayName: 'Hermes',
  gatewayType: 'hermes',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

const _openClawGateway = GatewayInfo(
  gatewayId: 'openclaw',
  displayName: 'OpenClaw',
  gatewayType: 'openclaw',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

const _disconnectedOpenClawGateway = GatewayInfo(
  gatewayId: 'openclaw',
  displayName: 'OpenClaw',
  gatewayType: 'openclaw',
  status: GatewayConnectionStatus.disconnected,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

class _FakeGatewayRepository implements GatewayRepository {
  _FakeGatewayRepository(this.gateways);

  final List<GatewayInfo> gateways;
  int syncCount = 0;
  final renamed = <String, String>{};

  @override
  Stream<List<GatewayInfo>> watchAll() => Stream.value(gateways);

  @override
  Stream<List<GatewayInfo>> watchOnline() => Stream.value(gateways);

  @override
  Future<List<GatewayInfo>> getOnlineGateways() async => gateways;

  @override
  Future<void> syncFromServer() async {
    syncCount += 1;
  }

  @override
  Future<void> markOnline(GatewayInfo gateway) async {}

  @override
  Future<void> markOffline(String gatewayId) async {}

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    renamed[gatewayId] = displayName;
  }
}

List<Override> _taskOverrides({
  required TasksApiService api,
  List<GatewayInfo> gateways = const [_hermesGateway],
}) {
  final repository = _FakeGatewayRepository(gateways);
  return [
    tasksApiServiceProvider.overrideWithValue(api),
    taskCacheRepositoryProvider.overrideWithValue(_ApiTaskCacheRepository(api)),
    gatewayRepositoryProvider.overrideWithValue(repository),
    gatewayListProvider.overrideWith((ref) => Stream.value(gateways)),
  ];
}

class _ApiTaskCacheRepository implements TaskCacheRepository {
  _ApiTaskCacheRepository(this.api);

  final TasksApiService api;

  @override
  Stream<List<ManagedTask>> watchTasks(String gatewayId) {
    return const Stream.empty();
  }

  @override
  Future<List<ManagedTask>> getTasks(String gatewayId) async {
    return const [];
  }

  @override
  Future<List<ManagedTask>> syncGateway(String gatewayId) {
    return api.listTasks(accountId: gatewayId);
  }

  @override
  Future<ManagedTask> create(TaskDraft draft) {
    return api.createTask(draft);
  }

  @override
  Future<ManagedTask> update(String id, TaskDraft draft) {
    return api.updateTask(id, draft);
  }

  @override
  Future<void> delete(ManagedTask task) {
    return api.deleteTask(task.id, task.accountId);
  }

  @override
  Future<ManagedTask?> setEnabled(ManagedTask task, bool enabled) {
    return api.setEnabled(task.id, task.accountId, enabled);
  }
}

class _TimeoutTasksApiService extends TasksApiService {
  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/tasks'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/tasks'),
        statusCode: 504,
        data: const {'error': 'gateway_timeout'},
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

class _ScopedTasksApiService extends TasksApiService {
  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    if (accountId == 'openclaw') {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/tasks'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/tasks'),
          statusCode: 504,
          data: const {'error': 'gateway_timeout'},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return const [
      ManagedTask(
        id: 'task_h',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Hermes task',
        schedule: '0 9 * * *',
        prompt: 'H',
        enabled: true,
        status: 'active',
      ),
    ];
  }
}

class _CountingTasksApiService extends TasksApiService {
  int listCalls = 0;

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    listCalls += 1;
    return [
      ManagedTask(
        id: 'task_$accountId',
        accountId: accountId ?? 'hermes',
        agent: accountId ?? 'Hermes',
        name: 'Task $accountId',
        schedule: '0 9 * * *',
        prompt: 'Prompt',
        enabled: true,
        status: 'active',
      ),
    ];
  }
}

class _LifecycleTasksApiService extends TasksApiService {
  List<ManagedTask> items = [
    const ManagedTask(
      id: 'task_daily',
      accountId: 'hermes',
      agent: 'Hermes',
      name: '每日总结',
      schedule: '0 9 * * *',
      scheduleText: '每天 09:00',
      prompt: '总结今天的事项',
      enabled: true,
      status: 'active',
      skills: ['notes'],
      lastRun: TaskRun(
        id: 'run_latest',
        taskId: 'task_daily',
        startedAt: '2026-04-24T09:00:00Z',
        status: 'success',
      ),
    ),
    const ManagedTask(
      id: 'task_error',
      accountId: 'hermes',
      agent: 'Hermes',
      name: '失败任务',
      schedule: '0 10 * * *',
      prompt: '会失败的任务',
      enabled: true,
      status: 'error',
    ),
  ];
  final runs = const [
    TaskRun(
      id: 'run_latest',
      taskId: 'task_daily',
      startedAt: '2026-04-24T09:00:00Z',
      finishedAt: '2026-04-24T09:03:00Z',
      status: 'success',
      outputPreview: '执行摘要',
    ),
  ];

  TaskDraft? createdDraft;
  TaskDraft? updatedDraft;
  String? updatedTaskId;
  String? deletedTaskId;
  String? toggledTaskId;
  bool? toggledEnabled;
  String? triggeredTaskId;
  String? outputRunId;

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    return items.where((task) => task.accountId == accountId).toList();
  }

  @override
  Future<ManagedTask> createTask(TaskDraft draft) async {
    createdDraft = draft;
    final task = ManagedTask(
      id: 'task_created',
      accountId: draft.accountId,
      agent: 'Hermes',
      name: draft.name,
      schedule: draft.schedule,
      prompt: draft.prompt,
      enabled: draft.enabled,
      status: 'active',
      skills: draft.skills,
      deliver: draft.deliver,
    );
    items = [...items, task];
    return task;
  }

  @override
  Future<ManagedTask> updateTask(String id, TaskDraft draft) async {
    updatedTaskId = id;
    updatedDraft = draft;
    final task = ManagedTask(
      id: id,
      accountId: draft.accountId,
      agent: 'Hermes',
      name: draft.name,
      schedule: draft.schedule,
      prompt: draft.prompt,
      enabled: draft.enabled,
      status: 'active',
      skills: draft.skills,
      deliver: draft.deliver,
    );
    items = [...items.where((item) => item.id != id), task];
    return task;
  }

  @override
  Future<void> deleteTask(String id, String accountId) async {
    deletedTaskId = id;
    items = items.where((task) => task.id != id).toList();
  }

  @override
  Future<ManagedTask?> setEnabled(
    String id,
    String accountId,
    bool enabled,
  ) async {
    toggledTaskId = id;
    toggledEnabled = enabled;
    final index = items.indexWhere((task) => task.id == id);
    final next = items[index].copyWith(enabled: enabled);
    items = [...items]..[index] = next;
    return next;
  }

  @override
  Future<TaskRun?> runTask(String id, String accountId) async {
    triggeredTaskId = id;
    return TaskRun(
      id: 'run_manual',
      taskId: id,
      startedAt: '2026-04-24T10:00:00Z',
      status: 'running',
    );
  }

  @override
  Future<List<TaskRun>> listRuns(String id, String accountId) async => runs;

  @override
  Future<String> getRunOutput(String id, String runId, String accountId) async {
    outputRunId = runId;
    return '完整执行结果';
  }
}

void main() {
  testWidgets('task list header follows skills center layout', (tester) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: _LifecycleTasksApiService()),
      screenSize: const Size(1280, 800),
      theme: ThemeData(
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 25),
          headlineSmall: TextStyle(fontSize: 27),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final title = tester.widget<Text>(find.text('任务管理'));
    expect(title.style?.fontWeight, FontWeight.w700);
    expect(title.style?.fontSize, 25);
    expect(find.byType(FilterChip), findsNWidgets(4));

    final titleRect = tester.getRect(find.text('任务管理'));
    final refreshRect = tester.getRect(find.byIcon(Icons.refresh).first);
    final newTaskRect = tester.getRect(
      find.widgetWithText(FilledButton, '新建任务'),
    );
    expect(refreshRect.left, greaterThan(titleRect.right));
    expect(newTaskRect.left, greaterThan(refreshRect.right));
  });

  testWidgets('task gateway errors only show gateway issue badge', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: _TimeoutTasksApiService()),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const ValueKey('app_notice_bar')), findsNothing);
    expect(
      find.byKey(const ValueKey('tasks_gateway_issue_hermes')),
      findsOneWidget,
    );
    expect(
      find.text('Hermes 网关响应超时，请确认 Hermes Gateway 正在运行后重试。'),
      findsNothing,
    );
  });

  testWidgets('disconnected gateway switch shows generic state', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(
        api: _ScopedTasksApiService(),
        gateways: const [_hermesGateway, _disconnectedOpenClawGateway],
      ),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Hermes task'), findsOneWidget);

    await tester.tap(find.text('openclaw'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hermes task'), findsNothing);
    expect(find.text('OpenClaw Gateway 未连接'), findsOneWidget);
    expect(find.text('当前不会发起任务请求'), findsOneWidget);
    expect(find.text('暂无任务'), findsNothing);
    expect(
      find.text('OpenClaw 网关响应超时，请确认 OpenClaw Gateway 正在运行后重试。'),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('tasks_gateway_issue_openclaw')),
      findsOneWidget,
    );
  });

  testWidgets('task screen renders searchable populated list', (tester) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: _LifecycleTasksApiService()),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('任务管理'), findsOneWidget);
    expect(find.text('每日总结'), findsOneWidget);
    expect(find.text('失败任务'), findsOneWidget);
    expect(find.text('全部 2'), findsOneWidget);
    expect(find.text('已启用 2'), findsOneWidget);
    expect(find.text('运行中 0'), findsOneWidget);
    expect(find.text('异常 1'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    expect(find.textContaining('上次成功'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '失败');
    await tester.pump();

    expect(find.text('每日总结'), findsNothing);
    expect(find.text('失败任务'), findsOneWidget);
  });

  testWidgets('desktop task list uses responsive two column cards', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [
      ...api.items,
      const ManagedTask(
        id: 'task_weekly',
        accountId: 'hermes',
        agent: 'Hermes',
        name: '每周代码审查报告',
        schedule: '0 9 * * 1',
        prompt: '汇总上周合并记录、测试失败和高风险模块。',
        enabled: true,
        status: 'active',
      ),
    ];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1700, 900),
    );

    await tester.pump();
    await tester.pump();

    final first = find.byKey(const ValueKey('task_card_task_daily'));
    final second = find.byKey(const ValueKey('task_card_task_error'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);

    final firstRect = tester.getRect(first);
    final secondRect = tester.getRect(second);
    expect(secondRect.left, greaterThan(firstRect.right));
    expect(secondRect.top, moreOrLessEquals(firstRect.top, epsilon: 1));
    expect(secondRect.width, moreOrLessEquals(firstRect.width, epsilon: 1));
  });

  testWidgets('task card follows demo structure and clamps description', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [
      const ManagedTask(
        id: 'task_long',
        accountId: 'hermes',
        agent: 'Hermes',
        name: '长描述任务',
        schedule: '0 7 * * *',
        prompt:
            '这是一段很长的任务描述，用于验证任务卡片最多显示三行内容，避免宽屏或窄屏下把卡片撑得过高，同时保持执行按钮和状态区域稳定靠右。',
        enabled: true,
        status: 'active',
        skills: ['web-search', 'github'],
      ),
    ];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    final card = find.byKey(const ValueKey('task_card_task_long'));
    final icon = find.byKey(const ValueKey('task_card_icon_task_long'));
    final main = find.byKey(const ValueKey('task_card_main_task_long'));
    final controls = find.byKey(const ValueKey('task_card_controls_task_long'));
    final descFinder = find.byKey(const ValueKey('task_card_desc_task_long'));
    expect(card, findsOneWidget);
    expect(icon, findsOneWidget);
    expect(main, findsOneWidget);
    expect(controls, findsOneWidget);
    expect(tester.getSize(icon), const Size(52, 52));
    expect(
      tester.getRect(controls).left,
      greaterThan(tester.getRect(main).left),
    );

    final desc = tester.widget<Text>(descFinder);
    expect(desc.maxLines, 3);
    expect(desc.overflow, TextOverflow.ellipsis);
  });

  testWidgets('task screen shows disconnected state when no gateway exists', (
    tester,
  ) async {
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(
        api: _LifecycleTasksApiService(),
        gateways: const [],
      ),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('暂无已连接 Gateway'), findsWidgets);
    expect(find.text('Hermes 或 OpenClaw 连接后即可管理任务。'), findsOneWidget);

    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();

    expect(find.text('计划'), findsNothing);
    expect(find.text('任务提示词'), findsNothing);
  });

  testWidgets('task empty state centers content vertically in its panel', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = const [];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    final panel = find.byKey(const ValueKey('empty_state_panel'));
    final content = find.byKey(const ValueKey('empty_state_panel_content'));
    expect(find.text('暂无任务'), findsOneWidget);
    expect(panel, findsOneWidget);
    expect(content, findsOneWidget);
    expect(tester.getRect(panel).bottom, greaterThan(760));
    expect(
      tester.getRect(content).center.dy,
      moreOrLessEquals(tester.getRect(panel).center.dy, epsilon: 1),
    );
  });

  testWidgets('task screen filters enabled running and error tasks', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [
      api.items.first,
      const ManagedTask(
        id: 'task_running',
        accountId: 'hermes',
        agent: 'Hermes',
        name: '运行任务',
        schedule: '0 11 * * *',
        prompt: '运行中的任务',
        enabled: true,
        status: 'active',
        lastRun: TaskRun(
          id: 'run_active',
          taskId: 'task_running',
          startedAt: '2026-04-24T11:00:00Z',
          status: 'running',
        ),
      ),
      api.items.last,
    ];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('每日总结'), findsOneWidget);
    expect(find.text('运行任务'), findsOneWidget);
    expect(find.text('失败任务'), findsOneWidget);

    await tester.tap(find.text('已启用 3').first);
    await tester.pump();

    expect(find.text('每日总结'), findsOneWidget);
    expect(find.text('失败任务'), findsOneWidget);
    expect(find.text('运行任务'), findsOneWidget);

    await tester.tap(find.text('运行中 1'));
    await tester.pump();

    expect(find.text('每日总结'), findsNothing);
    expect(find.text('失败任务'), findsNothing);
    expect(find.text('运行任务'), findsOneWidget);

    await tester.tap(find.text('异常 1'));
    await tester.pump();

    expect(find.text('每日总结'), findsNothing);
    expect(find.text('运行任务'), findsNothing);
    expect(find.text('失败任务'), findsOneWidget);
  });

  testWidgets('mobile task screen switches gateways through bottom sheet', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [
      api.items.first,
      const ManagedTask(
        id: 'task_openclaw',
        accountId: 'openclaw',
        agent: 'OpenClaw',
        name: 'OpenClaw 周报',
        schedule: '0 18 * * 5',
        prompt: '生成 OpenClaw 周报',
        enabled: true,
        status: 'active',
      ),
    ];

    await pumpApp(
      tester,
      const TasksManagementScreen(showAppBar: true),
      overrides: _taskOverrides(
        api: api,
        gateways: const [_hermesGateway, _openClawGateway],
      ),
      screenSize: const Size(430, 780),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('每日总结'), findsOneWidget);
    expect(find.text('OpenClaw 周报'), findsNothing);
    expect(
      tester.getSize(find.byType(TextField).first).width,
      greaterThan(390),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hermes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OpenClaw').last);
    await tester.pumpAndSettle();

    expect(find.text('每日总结'), findsNothing);
    expect(find.text('OpenClaw 周报'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('任务管理'), findsNothing);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
  });

  testWidgets('mobile task subpages do not keep the list app bar', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];

    await pumpApp(
      tester,
      const TasksManagementScreen(showAppBar: true),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(430, 780),
    );

    await tester.pump();
    await tester.pump();
    expect(find.text('任务管理'), findsOneWidget);

    await tester.tap(find.text('每日总结').first);
    await tester.pumpAndSettle();

    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('任务管理'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);

    final overviewPanel = find.byKey(const ValueKey('task_detail_overview'));
    expect(tester.getSize(overviewPanel).width, greaterThan(390));
    expect(tester.getTopLeft(overviewPanel).dx, lessThan(24));

    await tester.tap(find.text('执行记录').first);
    await tester.pumpAndSettle();
    final runsOverview = find.byKey(const ValueKey('task_runs_overview'));
    final runsListPanel = find.byKey(const ValueKey('task_runs_list_panel'));
    expect(tester.getSize(runsOverview).width, greaterThan(390));
    expect(tester.getSize(runsListPanel).width, greaterThan(390));
    expect(find.byIcon(Icons.check), findsNothing);

    final runPreview = find.text('执行摘要');
    final runAction = find.widgetWithText(OutlinedButton, '查看结果');
    expect(
      tester.getTopLeft(runAction).dy,
      greaterThan(tester.getBottomLeft(runPreview).dy),
    );

    await tester.tap(find.text('成功').first);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('task_output_info'))).width,
      greaterThan(390),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('task_output_content'))).width,
      greaterThan(390),
    );

    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('task_edit_basic_info'))).width,
      greaterThan(390),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('task_edit_prompt'))).width,
      greaterThan(390),
    );
  });

  testWidgets('task editor validates schedule and prompt before create', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_page_app_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_edit_basic_info')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_edit_prompt')), findsOneWidget);
    expect(find.textContaining('创建目标'), findsOneWidget);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(api.createdDraft, isNull);
    expect(find.text('必填'), findsNWidgets(2));
  });

  testWidgets('task screen creates a new agent-side task', (tester) async {
    final api = _LifecycleTasksApiService();
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '天气提醒');
    await tester.enterText(fields.at(1), '0 8 * * *');
    await tester.enterText(fields.at(2), 'local');
    await tester.enterText(fields.at(3), 'weather, notes');
    await tester.enterText(fields.at(4), '查询天气并提醒');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(api.createdDraft?.accountId, 'hermes');
    expect(api.createdDraft?.name, '天气提醒');
    expect(api.createdDraft?.skills, ['weather', 'notes']);
    expect(find.text('天气提醒'), findsWidgets);
  });

  testWidgets('new task stays in create mode after returning from detail', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('每日总结').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();

    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('编辑任务'), findsNothing);
    expect(find.textContaining('创建目标'), findsOneWidget);
    expect(find.text('每日总结'), findsNothing);
  });

  testWidgets('task list run button requires confirmation before API trigger', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '立即执行').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('确认立即执行任务'), findsOneWidget);
    expect(api.triggeredTaskId, isNull);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(api.triggeredTaskId, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '立即执行').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
    await tester.pumpAndSettle();

    expect(api.triggeredTaskId, 'task_daily');
    final snackBar = find.byType(SnackBar);
    expect(snackBar, findsOneWidget);
    expect(tester.widget<SnackBar>(snackBar).width, 480);
  });

  testWidgets('task list run history back returns to task management', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('任务管理'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '执行记录').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_runs_list_panel')), findsOneWidget);
    expect(find.text('任务详情'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();

    expect(find.text('任务管理'), findsOneWidget);
    expect(find.text('每日总结'), findsOneWidget);
    expect(find.byKey(const ValueKey('task_runs_list_panel')), findsNothing);
    expect(find.text('任务详情'), findsNothing);
  });

  testWidgets('task screen opens detail edit and run pages from the list', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];
    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, '编辑'), findsNothing);

    await tester.tap(find.text('每日总结').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_page_app_bar')), findsOneWidget);
    expect(find.text('任务详情'), findsOneWidget);
    expect(find.text('返回任务列表'), findsNothing);
    expect(find.byKey(const ValueKey('task_detail_overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_detail_prompt')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_detail_definition')), findsNothing);
    expect(find.byKey(const ValueKey('task_detail_recent')), findsNothing);
    expect(find.byKey(const ValueKey('task_detail_execution')), findsNothing);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('任务定义'), findsOneWidget);
    expect(find.text('最近状态'), findsOneWidget);
    expect(find.text('任务提示词'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('编辑任务'), findsNothing);

    final overviewPanel = find.byKey(const ValueKey('task_detail_overview'));
    final promptPanel = find.byKey(const ValueKey('task_detail_prompt'));
    expect(
      tester.getSize(overviewPanel).width,
      tester.getSize(promptPanel).width,
    );

    await tester.tap(find.text('执行记录').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_runs_overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_runs_list_panel')), findsOneWidget);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('运行概览'), findsOneWidget);
    expect(find.text('任务摘要'), findsNothing);
    expect(find.byKey(const ValueKey('task_page_app_bar')), findsOneWidget);
    expect(find.text('返回详情'), findsNothing);
    expect(find.textContaining('2026-04-24T09:00:00Z'), findsNothing);
    expect(find.textContaining('2026-04-24T09:03:00Z'), findsNothing);
    expect(find.textContaining('执行摘要'), findsOneWidget);
    expect(find.text('查看结果'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '立即执行'), findsNothing);
    expect(find.widgetWithText(FilledButton, '编辑任务'), findsNothing);

    await tester.tap(find.text('成功').first);
    await tester.pumpAndSettle();
    expect(api.outputRunId, 'run_latest');
    expect(find.text('执行结果'), findsOneWidget);
    expect(find.text('返回执行记录'), findsNothing);
    expect(find.byKey(const ValueKey('task_output_info')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_output_content')), findsOneWidget);
    expect(find.text('输出内容'), findsOneWidget);
    final copyButton = find.widgetWithText(TextButton, '复制');
    expect(copyButton, findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '复制'), findsNothing);
    expect(
      (tester.getCenter(copyButton).dy - tester.getCenter(find.text('输出内容')).dy)
          .abs(),
      lessThan(12),
    );
    expect(find.text('导出'), findsNothing);
    expect(find.text('完整执行结果'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('task_page_app_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_edit_basic_info')), findsOneWidget);
    expect(find.byKey(const ValueKey('task_edit_prompt')), findsOneWidget);
    expect(find.text('保存时提交到当前 Gateway。提示词是 Agent 执行任务的主体内容。'), findsOneWidget);
    expect(find.text('立即执行一次'), findsNothing);
    expect(find.text('删除任务'), findsWidgets);
    expect(find.text('取消'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('任务提示词'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '每日总结 v2');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.updatedTaskId, 'task_daily');
    expect(api.updatedDraft?.name, '每日总结 v2');
    expect(find.text('每日总结 v2'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('task_app_bar_back')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.toggledTaskId, 'task_daily');
    expect(api.toggledEnabled, false);

    await tester.tap(find.widgetWithText(FilledButton, '立即执行').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('确认立即执行任务'), findsOneWidget);
    expect(api.triggeredTaskId, isNull);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(api.triggeredTaskId, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '立即执行').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认执行'));
    await tester.pumpAndSettle();
    expect(api.triggeredTaskId, 'task_daily');

    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('task editor deletes an existing task from danger zone', (
    tester,
  ) async {
    final api = _LifecycleTasksApiService();
    api.items = [api.items.first];

    await pumpApp(
      tester,
      const TasksManagementScreen(),
      overrides: _taskOverrides(api: api),
      screenSize: const Size(1280, 800),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('每日总结').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('task_page_app_bar')), findsOneWidget);
    expect(find.text('危险操作'), findsOneWidget);
    await tester.ensureVisible(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('删除任务？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(api.deletedTaskId, 'task_daily');
    expect(find.text('每日总结'), findsNothing);
    expect(find.text('暂无任务'), findsOneWidget);
  });

  testWidgets(
    'selecting disconnected task gateway shows generic state without request',
    (tester) async {
      final api = _CountingTasksApiService();
      await pumpApp(
        tester,
        const TasksManagementScreen(),
        overrides: _taskOverrides(
          api: api,
          gateways: const [_hermesGateway, _disconnectedOpenClawGateway],
        ),
        screenSize: const Size(1280, 800),
      );
      await tester.pump();
      await tester.pump();
      final callsAfterInitialLoad = api.listCalls;

      await tester.tap(find.text('openclaw').first);
      await tester.pumpAndSettle();

      expect(api.listCalls, callsAfterInitialLoad);
      expect(find.text('任务管理'), findsOneWidget);
      expect(find.text('搜索任务...'), findsOneWidget);
      expect(find.text('OpenClaw Gateway 未连接'), findsOneWidget);
      expect(find.text('当前不会发起任务请求'), findsOneWidget);
      expect(find.text('暂无任务'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '刷新'), findsNothing);

      final refreshFinder = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.refresh,
      );
      expect(refreshFinder, findsOneWidget);
      final refreshButton = tester.widget<IconButton>(refreshFinder);
      expect(refreshButton.onPressed, isNull);
      final newTaskButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '新建任务'),
      );
      expect(newTaskButton.onPressed, isNull);
    },
  );
}
