class TaskAccount {
  final String accountId;
  final String agentName;

  const TaskAccount({required this.accountId, required this.agentName});
}

class ManagedTask {
  final String id;
  final String accountId;
  final String agent;
  final String name;
  final String schedule;
  final String? scheduleText;
  final String prompt;
  final bool enabled;
  final String status;
  final List<String> skills;
  final String? deliver;
  final String? nextRunAt;
  final TaskRun? lastRun;
  final String? createdAt;
  final String? updatedAt;

  const ManagedTask({
    required this.id,
    required this.accountId,
    required this.agent,
    required this.name,
    required this.schedule,
    this.scheduleText,
    required this.prompt,
    required this.enabled,
    required this.status,
    this.skills = const [],
    this.deliver,
    this.nextRunAt,
    this.lastRun,
    this.createdAt,
    this.updatedAt,
  });

  factory ManagedTask.fromJson(Map<String, dynamic> json) {
    return ManagedTask(
      id: json['id'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      agent: json['agent'] as String? ?? '',
      name: json['name'] as String? ?? '',
      schedule: json['schedule'] as String? ?? '',
      scheduleText: json['schedule_text'] as String?,
      prompt: json['prompt'] as String? ?? '',
      enabled: json['enabled'] != false,
      status: json['status'] as String? ?? 'active',
      skills: (json['skills'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      deliver: json['deliver'] as String?,
      nextRunAt: json['next_run_at'] as String?,
      lastRun: json['last_run'] is Map
          ? TaskRun.fromJson(Map<String, dynamic>.from(json['last_run'] as Map))
          : null,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  ManagedTask copyWith({bool? enabled, String? status, TaskRun? lastRun}) {
    return ManagedTask(
      id: id,
      accountId: accountId,
      agent: agent,
      name: name,
      schedule: schedule,
      scheduleText: scheduleText,
      prompt: prompt,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      skills: skills,
      deliver: deliver,
      nextRunAt: nextRunAt,
      lastRun: lastRun ?? this.lastRun,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

class TaskDraft {
  final String accountId;
  final String name;
  final String schedule;
  final String prompt;
  final bool enabled;
  final List<String> skills;
  final String? deliver;

  const TaskDraft({
    required this.accountId,
    required this.name,
    required this.schedule,
    required this.prompt,
    this.enabled = true,
    this.skills = const [],
    this.deliver,
  });

  factory TaskDraft.fromTask(ManagedTask task) {
    return TaskDraft(
      accountId: task.accountId,
      name: task.name,
      schedule: task.schedule,
      prompt: task.prompt,
      enabled: task.enabled,
      skills: task.skills,
      deliver: task.deliver,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      if (name.trim().isNotEmpty) 'name': name.trim(),
      'schedule': schedule.trim(),
      'prompt': prompt.trim(),
      'enabled': enabled,
      if (skills.isNotEmpty) 'skills': skills,
      if (deliver != null && deliver!.trim().isNotEmpty)
        'deliver': deliver!.trim(),
    };
  }

  Map<String, dynamic> toPatchJson() {
    final json = toJson();
    json.remove('account_id');
    return json;
  }
}

class TaskRun {
  final String id;
  final String taskId;
  final String startedAt;
  final String? finishedAt;
  final String status;
  final String? outputPreview;
  final String? error;

  const TaskRun({
    required this.id,
    required this.taskId,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    this.outputPreview,
    this.error,
  });

  factory TaskRun.fromJson(Map<String, dynamic> json) {
    return TaskRun(
      id: json['id'] as String? ?? '',
      taskId: json['task_id'] as String? ?? '',
      startedAt: json['started_at'] as String? ?? '',
      finishedAt: json['finished_at'] as String?,
      status: json['status'] as String? ?? 'running',
      outputPreview: json['output_preview'] as String?,
      error: json['error'] as String?,
    );
  }
}
