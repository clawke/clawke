import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_task.dart';
import 'package:client/providers/tasks_provider.dart';
import 'package:client/services/tasks_api_service.dart';

class _FakeTasksApiService extends TasksApiService {
  List<ManagedTask> items;
  final List<TaskRun> runItems;
  String? listedAccountId;
  String? toggledTaskId;
  bool? toggledEnabled;
  String? triggeredTaskId;
  String? outputRunId;

  _FakeTasksApiService(this.items, {this.runItems = const []});

  @override
  Future<List<ManagedTask>> listTasks({String? accountId}) async {
    listedAccountId = accountId;
    return items.where((task) => task.accountId == accountId).toList();
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
      id: 'run_1',
      taskId: id,
      startedAt: '2026-04-24T00:00:00Z',
      status: 'running',
    );
  }

  @override
  Future<List<TaskRun>> listRuns(String id, String accountId) async {
    return runItems;
  }

  @override
  Future<String> getRunOutput(String id, String runId, String accountId) async {
    outputRunId = runId;
    return 'done';
  }
}

void main() {
  test('TasksController loads tasks for the first connected gateway', () async {
    final fake = _FakeTasksApiService([
      const ManagedTask(
        id: 'task_1',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Daily summary',
        schedule: '0 9 * * *',
        prompt: 'Summarize',
        enabled: true,
        status: 'active',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [tasksApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    ]);

    final state = container.read(tasksControllerProvider);
    expect(state.selectedAccountId, 'hermes');
    expect(state.tasks.single.name, 'Daily summary');
    expect(fake.listedAccountId, 'hermes');
  });

  test('TasksController switches gateway and reloads scoped tasks', () async {
    final fake = _FakeTasksApiService([
      const ManagedTask(
        id: 'task_h',
        accountId: 'hermes',
        agent: 'Hermes',
        name: 'Hermes task',
        schedule: '0 9 * * *',
        prompt: 'H',
        enabled: true,
        status: 'active',
      ),
      const ManagedTask(
        id: 'task_o',
        accountId: 'openclaw',
        agent: 'OpenClaw',
        name: 'OpenClaw task',
        schedule: '0 10 * * *',
        prompt: 'O',
        enabled: true,
        status: 'active',
      ),
    ]);
    final container = ProviderContainer(
      overrides: [tasksApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
      TaskAccount(accountId: 'openclaw', agentName: 'OpenClaw'),
    ]);
    await container
        .read(tasksControllerProvider.notifier)
        .selectAccount('openclaw');

    final state = container.read(tasksControllerProvider);
    expect(state.selectedAccountId, 'openclaw');
    expect(state.tasks.single.id, 'task_o');
  });

  test('TasksController toggles task and triggers run output chain', () async {
    const run = TaskRun(
      id: 'run_done',
      taskId: 'task_1',
      startedAt: '2026-04-24T00:00:00Z',
      status: 'success',
      outputPreview: 'done',
    );
    const task = ManagedTask(
      id: 'task_1',
      accountId: 'hermes',
      agent: 'Hermes',
      name: 'Daily summary',
      schedule: '0 9 * * *',
      prompt: 'Summarize',
      enabled: true,
      status: 'active',
    );
    final fake = _FakeTasksApiService([task], runItems: [run]);
    final container = ProviderContainer(
      overrides: [tasksApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(tasksControllerProvider.notifier).syncAccounts(const [
      TaskAccount(accountId: 'hermes', agentName: 'Hermes'),
    ]);
    await container
        .read(tasksControllerProvider.notifier)
        .setEnabled(task, false);
    await container.read(tasksControllerProvider.notifier).runNow(task);
    await container.read(tasksControllerProvider.notifier).loadRuns(task);
    await container.read(tasksControllerProvider.notifier).loadOutput(run);

    final state = container.read(tasksControllerProvider);
    expect(fake.toggledTaskId, 'task_1');
    expect(fake.toggledEnabled, false);
    expect(fake.triggeredTaskId, 'task_1');
    expect(state.runs.first.id, 'run_done');
    expect(state.selectedRunOutput, 'done');
  });
}
