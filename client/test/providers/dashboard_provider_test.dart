import 'dart:async';

import 'package:client/models/gateway_info.dart';
import 'package:client/models/usage_dashboard.dart';
import 'package:client/providers/dashboard_provider.dart';
import 'package:client/services/dashboard_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _hermesGateway = GatewayInfo(
  gatewayId: 'hermes',
  displayName: 'Hermes',
  gatewayType: 'hermes',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'models', 'skills', 'tasks'],
);

const _openClawGateway = GatewayInfo(
  gatewayId: 'openclaw',
  displayName: 'OpenClaw',
  gatewayType: 'openclaw',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'models', 'skills', 'tasks'],
);

class _FakeDashboardApiService extends DashboardApiService {
  final Map<String, UsageDashboard> dashboards;
  final Object? error;
  final requests = <String?>[];

  _FakeDashboardApiService(this.dashboards, {this.error});

  @override
  Future<UsageDashboard> getUsage({String? gatewayId}) async {
    requests.add(gatewayId);
    final currentError = error;
    if (currentError != null) throw currentError;
    return dashboards[gatewayId] ??
        UsageDashboard(
          gatewayId: gatewayId ?? '',
          summary: const UsageTotals(),
          today: const UsageTotals(),
          hourly: const [],
          daily: const [],
          models: const [],
          recent: const [],
        );
  }
}

void main() {
  test(
    'DashboardController selects first online gateway and loads usage',
    () async {
      final api = _FakeDashboardApiService({
        'hermes': _dashboard('hermes', 100),
        'openclaw': _dashboard('openclaw', 200),
      });
      final container = ProviderContainer(
        overrides: [dashboardApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(dashboardControllerProvider.notifier).syncGateways([
        _hermesGateway,
        _openClawGateway,
      ]);

      final state = container.read(dashboardControllerProvider);
      expect(state.selectedGatewayId, 'hermes');
      expect(state.dashboard?.summary.total, 100);
      expect(api.requests, ['hermes']);
    },
  );

  test(
    'DashboardController switches gateway and ignores stale response',
    () async {
      final api = _DelayedDashboardApiService();
      final container = ProviderContainer(
        overrides: [dashboardApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      unawaited(
        container.read(dashboardControllerProvider.notifier).syncGateways([
          _hermesGateway,
          _openClawGateway,
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      unawaited(
        container
            .read(dashboardControllerProvider.notifier)
            .selectGateway('openclaw'),
      );
      await Future<void>.delayed(Duration.zero);

      api.complete('openclaw', total: 200);
      await Future<void>.delayed(Duration.zero);
      api.complete('hermes', total: 100);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(dashboardControllerProvider);
      expect(state.selectedGatewayId, 'openclaw');
      expect(state.dashboard?.gatewayId, 'openclaw');
      expect(state.dashboard?.summary.total, 200);
    },
  );

  test('DashboardController stores readable API errors', () async {
    final api = _FakeDashboardApiService(
      const {},
      error: DioException(
        requestOptions: RequestOptions(path: '/api/dashboard/usage'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/dashboard/usage'),
          statusCode: 503,
          data: {'error': 'dashboard_unavailable'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );
    final container = ProviderContainer(
      overrides: [dashboardApiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(dashboardControllerProvider.notifier).syncGateways([
      _hermesGateway,
    ]);

    final state = container.read(dashboardControllerProvider);
    expect(state.errorGatewayId, 'hermes');
    expect(state.errorMessage, 'dashboard_unavailable');
  });
}

class _DelayedDashboardApiService extends DashboardApiService {
  final _pending = <String, Completer<UsageDashboard>>{};

  @override
  Future<UsageDashboard> getUsage({String? gatewayId}) {
    final id = gatewayId ?? '';
    final completer = Completer<UsageDashboard>();
    _pending[id] = completer;
    return completer.future;
  }

  void complete(String gatewayId, {required int total}) {
    _pending.remove(gatewayId)?.complete(_dashboard(gatewayId, total));
  }
}

UsageDashboard _dashboard(String gatewayId, int total) {
  return UsageDashboard(
    gatewayId: gatewayId,
    summary: UsageTotals(total: total, input: total ~/ 2, output: total ~/ 2),
    today: UsageTotals(total: total),
    hourly: [UsageHourlyPoint(hour: '13:00', total: total)],
    daily: [UsageDailyPoint(date: '2026-05-11', total: total)],
    models: [
      UsageModelSummary(
        model: 'claude-sonnet',
        provider: 'anthropic',
        calls: 1,
        total: total,
      ),
    ],
    recent: [
      UsageRecentRecord(
        gatewayId: gatewayId,
        conversationId: 'conv_1',
        model: 'claude-sonnet',
        provider: 'anthropic',
        createdAt: 1778500000000,
        total: total,
      ),
    ],
  );
}
