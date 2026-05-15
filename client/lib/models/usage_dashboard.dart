class UsageTotals {
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;
  final int reasoning;
  final int total;

  const UsageTotals({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.reasoning = 0,
    this.total = 0,
  });

  factory UsageTotals.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UsageTotals();
    return UsageTotals(
      input: _asInt(json['input']),
      output: _asInt(json['output']),
      cacheRead: _asInt(json['cacheRead'] ?? json['cache_read']),
      cacheWrite: _asInt(json['cacheWrite'] ?? json['cache_write']),
      reasoning: _asInt(json['reasoning']),
      total: _asInt(json['total']),
    );
  }

  bool get isEmpty =>
      input == 0 &&
      output == 0 &&
      cacheRead == 0 &&
      cacheWrite == 0 &&
      reasoning == 0 &&
      total == 0;
}

class UsageHourlyPoint {
  final String hour;
  final int total;

  const UsageHourlyPoint({required this.hour, required this.total});

  factory UsageHourlyPoint.fromJson(Map<String, dynamic> json) {
    return UsageHourlyPoint(
      hour: json['hour'] as String? ?? '',
      total: _asInt(json['total'] ?? json['tokens']),
    );
  }
}

class UsageDailyPoint extends UsageTotals {
  final String date;

  const UsageDailyPoint({
    required this.date,
    super.input,
    super.output,
    super.cacheRead,
    super.cacheWrite,
    super.reasoning,
    super.total,
  });

  factory UsageDailyPoint.fromJson(Map<String, dynamic> json) {
    return UsageDailyPoint(
      date: json['date'] as String? ?? '',
      input: _asInt(json['input']),
      output: _asInt(json['output']),
      cacheRead: _asInt(json['cacheRead'] ?? json['cache_read']),
      cacheWrite: _asInt(json['cacheWrite'] ?? json['cache_write']),
      reasoning: _asInt(json['reasoning']),
      total: _asInt(json['total']),
    );
  }
}

class UsageModelSummary extends UsageTotals {
  final String model;
  final String provider;
  final int calls;

  const UsageModelSummary({
    required this.model,
    required this.provider,
    required this.calls,
    super.input,
    super.output,
    super.cacheRead,
    super.cacheWrite,
    super.reasoning,
    super.total,
  });

  factory UsageModelSummary.fromJson(Map<String, dynamic> json) {
    return UsageModelSummary(
      model: json['model'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      calls: _asInt(json['calls']),
      input: _asInt(json['input']),
      output: _asInt(json['output']),
      cacheRead: _asInt(json['cacheRead'] ?? json['cache_read']),
      cacheWrite: _asInt(json['cacheWrite'] ?? json['cache_write']),
      reasoning: _asInt(json['reasoning']),
      total: _asInt(json['total']),
    );
  }
}

class UsageRecentRecord extends UsageTotals {
  final String gatewayId;
  final String conversationId;
  final String model;
  final String provider;
  final int createdAt;

  const UsageRecentRecord({
    required this.gatewayId,
    required this.conversationId,
    required this.model,
    required this.provider,
    required this.createdAt,
    super.input,
    super.output,
    super.cacheRead,
    super.cacheWrite,
    super.reasoning,
    super.total,
  });

  factory UsageRecentRecord.fromJson(Map<String, dynamic> json) {
    return UsageRecentRecord(
      gatewayId: json['gateway_id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      model: json['model'] as String? ?? '',
      provider: json['provider'] as String? ?? '',
      createdAt: _asInt(json['created_at']),
      input: _asInt(json['input']),
      output: _asInt(json['output']),
      cacheRead: _asInt(json['cacheRead'] ?? json['cache_read']),
      cacheWrite: _asInt(json['cacheWrite'] ?? json['cache_write']),
      reasoning: _asInt(json['reasoning']),
      total: _asInt(json['total']),
    );
  }
}

class UsageDashboard {
  final String gatewayId;
  final UsageTotals summary;
  final UsageTotals today;
  final List<UsageHourlyPoint> hourly;
  final List<UsageDailyPoint> daily;
  final List<UsageModelSummary> models;
  final List<UsageRecentRecord> recent;
  final int todayMessages;
  final int totalConversations;

  const UsageDashboard({
    required this.gatewayId,
    required this.summary,
    required this.today,
    required this.hourly,
    required this.daily,
    required this.models,
    required this.recent,
    this.todayMessages = 0,
    this.totalConversations = 0,
  });

  factory UsageDashboard.fromJson(Map<String, dynamic> json) {
    return UsageDashboard(
      gatewayId: json['gateway_id'] as String? ?? '',
      summary: UsageTotals.fromJson(_asMap(json['summary'])),
      today: UsageTotals.fromJson(_asMap(json['today'])),
      hourly: _asList(
        json['hourly'],
      ).map((item) => UsageHourlyPoint.fromJson(item)).toList(),
      daily: _asList(
        json['daily'],
      ).map((item) => UsageDailyPoint.fromJson(item)).toList(),
      models: _asList(
        json['models'],
      ).map((item) => UsageModelSummary.fromJson(item)).toList(),
      recent: _asList(
        json['recent'],
      ).map((item) => UsageRecentRecord.fromJson(item)).toList(),
      todayMessages: _asInt(json['todayMessages'] ?? json['today_messages']),
      totalConversations: _asInt(
        json['totalConversations'] ?? json['total_conversations'],
      ),
    );
  }

  bool get hasUsage =>
      !summary.isEmpty ||
      !today.isEmpty ||
      hourly.any((point) => point.total > 0) ||
      daily.any((point) => point.total > 0) ||
      models.isNotEmpty ||
      recent.isNotEmpty ||
      todayMessages > 0 ||
      totalConversations > 0;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
