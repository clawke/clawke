import 'dart:async';

import 'package:client/models/gateway_info.dart';
import 'package:client/models/sdui_component_model.dart';
import 'package:client/models/usage_dashboard.dart';
import 'package:client/providers/dashboard_provider.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/widgets/dashboard_view.dart';
import 'package:client/widgets/empty_state_panel.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:client/widgets/gateway_unavailable_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashboardManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const DashboardManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<DashboardManagementScreen> createState() =>
      _DashboardManagementScreenState();
}

class _DashboardManagementScreenState
    extends ConsumerState<DashboardManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGatewayCache();
      _syncGateways();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<GatewayInfo>>>(gatewayListProvider, (_, next) {
      final gateways = next.valueOrNull;
      if (gateways != null) unawaited(_syncGateways(gateways));
    });

    final state = ref.watch(dashboardControllerProvider);
    final gateways =
        ref.watch(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final colorScheme = Theme.of(context).colorScheme;

    final content = Container(
      color: colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final unavailableGateway = _selectedUnavailableGateway(
            gateways,
            state,
          );
          final body = _buildBody(
            state,
            gateways,
            unavailableGateway: unavailableGateway,
            compact: !wide,
          );

          if (!wide) return body;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GatewaySelectorPane(
                gateways: gateways,
                selectedGatewayId: state.selectedGatewayId,
                capability: dashboardGatewayCapability,
                errorGatewayId:
                    state.errorGatewayId ?? unavailableGateway?.gatewayId,
                issueKeyPrefix: 'dashboard_gateway_issue',
                onSelected: _selectGateway,
                onRename: (gatewayId, displayName) => ref
                    .read(gatewayRepositoryProvider)
                    .renameGateway(gatewayId, displayName),
              ),
              Expanded(child: body),
            ],
          );
        },
      ),
    );

    if (!widget.showAppBar) return content;
    return Scaffold(appBar: _buildAppBar(state, gateways), body: content);
  }

  PreferredSizeWidget _buildAppBar(
    DashboardState state,
    List<GatewayInfo> gateways,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final unavailableGateway = _selectedUnavailableGateway(gateways, state);
    final hasGatewayIssue =
        unavailableGateway != null || state.errorGatewayId != null;
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
      title: Text(_localized(context, 'Dashboard', '仪表盘')),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: _localized(context, 'Refresh', '刷新'),
          onPressed: state.isLoading || hasGatewayIssue
              ? null
              : () => unawaited(_refreshDashboard(gateways)),
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
    final state = ref.read(dashboardControllerProvider);
    final ordered = orderGatewaysForSelection(
      source,
      dashboardGatewayCapability,
      currentGatewayId: state.selectedGatewayId,
    );
    final selected = gatewayForSelection(
      source,
      dashboardGatewayCapability,
      currentGatewayId: state.selectedGatewayId,
    );
    if (selected != null &&
        gatewayUnavailableFor(selected, dashboardGatewayCapability)) {
      _markDashboardGatewayUnavailable(ordered, selected);
      return;
    }
    await ref.read(dashboardControllerProvider.notifier).syncGateways(ordered);
  }

  Future<void> _refreshDashboard(List<GatewayInfo> gateways) {
    final state = ref.read(dashboardControllerProvider);
    final selected = gatewayById(gateways, state.selectedGatewayId);
    if (selected != null &&
        gatewayUnavailableFor(selected, dashboardGatewayCapability)) {
      _markDashboardGatewayUnavailable(
        orderGatewaysForSelection(
          gateways,
          dashboardGatewayCapability,
          currentGatewayId: selected.gatewayId,
        ),
        selected,
      );
      return Future.value();
    }
    return ref.read(dashboardControllerProvider.notifier).refresh();
  }

  void _selectGateway(String gatewayId) {
    final gateways =
        ref.read(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final selected = gatewayById(gateways, gatewayId);
    if (selected != null &&
        gatewayUnavailableFor(selected, dashboardGatewayCapability)) {
      _markDashboardGatewayUnavailable(
        orderGatewaysForSelection(
          gateways,
          dashboardGatewayCapability,
          currentGatewayId: gatewayId,
        ),
        selected,
      );
      return;
    }
    unawaited(
      ref.read(dashboardControllerProvider.notifier).selectGateway(gatewayId),
    );
  }

  void _markDashboardGatewayUnavailable(
    List<GatewayInfo> gateways,
    GatewayInfo gateway,
  ) {
    ref
        .read(dashboardControllerProvider.notifier)
        .selectUnavailableGateway(
          gateways,
          gateway.gatewayId,
          gatewayUnavailableStateMessage(context, gateway),
        );
  }

  GatewayInfo? _selectedUnavailableGateway(
    List<GatewayInfo> gateways,
    DashboardState state,
  ) {
    final selected = gatewayById(gateways, state.selectedGatewayId);
    if (selected == null) return null;
    if (!gatewayUnavailableFor(selected, dashboardGatewayCapability)) {
      return null;
    }
    return selected;
  }

  Widget _buildBody(
    DashboardState state,
    List<GatewayInfo> gateways, {
    required GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    if (unavailableGateway != null) {
      return GatewayUnavailablePanel(
        title: gatewayUnavailableTitle(
          context,
          unavailableGateway,
          capability: dashboardGatewayCapability,
          capabilityNameZh: '仪表盘',
          capabilityNameEn: 'dashboard',
        ),
        message: gatewayUnavailableStateMessage(context, unavailableGateway),
        footnote: _localized(
          context,
          'Reconnect this gateway, then refresh the dashboard.',
          '重新连接该 Gateway 后刷新仪表盘。',
        ),
      );
    }

    final hasGateways = state.gateways.isNotEmpty || gateways.isNotEmpty;
    if (!hasGateways) {
      return Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: EmptyStatePanel(
          icon: Icons.dashboard_outlined,
          title: _localized(context, 'No gateway connected', '暂无已连接 Gateway'),
          message: _localized(
            context,
            'Connect a gateway before viewing token usage.',
            '连接 Gateway 后即可查看 token 用量。',
          ),
        ),
      );
    }

    if (state.dashboard == null && state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => _refreshDashboard(gateways),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 28,
              compact ? 16 : 28,
              compact ? 16 : 28,
              compact ? 20 : 32,
            ),
            sliver: SliverToBoxAdapter(
              child: _DashboardContent(
                dashboard: state.dashboard,
                state: state,
                gateways: gateways,
                compact: compact,
                onGatewaySelected: _selectGateway,
                onClearError: () =>
                    ref.read(dashboardControllerProvider.notifier).clearError(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final UsageDashboard? dashboard;
  final DashboardState state;
  final List<GatewayInfo> gateways;
  final bool compact;
  final ValueChanged<String> onGatewaySelected;
  final VoidCallback onClearError;

  const _DashboardContent({
    required this.dashboard,
    required this.state,
    required this.gateways,
    required this.compact,
    required this.onGatewaySelected,
    required this.onClearError,
  });

  @override
  Widget build(BuildContext context) {
    final selected = gatewayById(gateways, state.selectedGatewayId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact) ...[
          GatewayMobileSelectorButton(
            gateways: gateways,
            selectedGatewayId: state.selectedGatewayId,
            capability: dashboardGatewayCapability,
            errorGatewayId: state.errorGatewayId,
            issueKeyPrefix: 'dashboard_gateway_issue',
            onSelected: onGatewaySelected,
          ),
          const SizedBox(height: 18),
        ],
        if (state.errorMessage != null) ...[
          _ErrorBanner(message: state.errorMessage!, onDismiss: onClearError),
          const SizedBox(height: 16),
        ],
        if (dashboard == null)
          EmptyStatePanel(
            icon: Icons.query_stats,
            title: _localized(context, 'No usage data', '暂无用量数据'),
            message: _localized(
              context,
              'Send a message through this gateway, then refresh.',
              '通过该 Gateway 发送消息后刷新即可看到数据。',
            ),
          )
        else
          DashboardView(
            component: _dashboardComponent(
              context,
              dashboard!,
              selected,
              gateways,
            ),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.36)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            color: colorScheme.onErrorContainer,
            tooltip: _localized(context, 'Dismiss', '关闭'),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

SduiComponentModel _dashboardComponent(
  BuildContext context,
  UsageDashboard dashboard,
  GatewayInfo? selected,
  List<GatewayInfo> gateways,
) {
  final connected = selected?.status == GatewayConnectionStatus.online;
  final gatewayName = selected == null
      ? _localized(context, 'Gateway', 'Gateway')
      : gatewayDisplayName(selected);
  final onlineGateways = gateways
      .where((gateway) => gateway.status == GatewayConnectionStatus.online)
      .length;
  final cacheTotal = dashboard.summary.cacheRead + dashboard.summary.cacheWrite;
  final todayCache = dashboard.today.cacheRead + dashboard.today.cacheWrite;

  return SduiComponentModel(
    widgetName: 'DashboardView',
    actions: const [],
    props: {
      'sections': [
        {
          'title': _localized(context, 'Gateway Status', '网关状态'),
          'type': 'status_cards',
          'items': [
            {
              'label': '$gatewayName Gateway',
              'value': connected ? 'Connected' : 'Disconnected',
              'status': connected ? 'ok' : 'error',
            },
            {
              'label': 'Uptime',
              'value': _formatUptime(selected),
              'status': connected ? 'ok' : 'error',
            },
            {
              'label': 'Gateways',
              'value': '$onlineGateways online',
              'status': onlineGateways > 0 ? 'ok' : 'error',
            },
          ],
        },
        {
          'title': _localized(context, 'Token Usage', 'Token 用量'),
          'type': 'stats_grid',
          'items': [
            {
              'label': 'Total Tokens',
              'value': _formatTokens(dashboard.summary.total),
              'subtext':
                  '${_formatTokens(dashboard.summary.input)} in / ${_formatTokens(dashboard.summary.output)} out · Cache: ${_formatTokens(cacheTotal)}',
            },
            {
              'label': 'Today Tokens',
              'value': _formatTokens(dashboard.today.total),
              'subtext':
                  '${_formatTokens(dashboard.today.input)} in / ${_formatTokens(dashboard.today.output)} out · Cache: ${_formatTokens(todayCache)}',
            },
            {
              'label': _localized(context, 'Today Messages', '今日消息'),
              'value': dashboard.todayMessages.toString(),
            },
            {
              'label': _localized(context, 'Total Conversations', '总会话'),
              'value': dashboard.totalConversations.toString(),
            },
          ],
        },
        {
          'title': _localized(context, 'Hourly Token Usage', '每小时 Token 用量'),
          'type': 'line_chart',
          'data': [
            for (final point in dashboard.hourly)
              {'hour': point.hour, 'tokens': point.total},
          ],
        },
        {
          'title': _localized(
            context,
            'Daily Token Usage (30d)',
            '每日 Token 用量（30天）',
          ),
          'type': 'bar_chart',
          'data': [
            for (final point in dashboard.daily)
              {
                'date': point.date,
                'input': point.input,
                'output': point.output,
                'cache': point.cacheRead + point.cacheWrite,
              },
          ],
        },
      ],
    },
  );
}

String _formatUptime(GatewayInfo? gateway) {
  final connectedAt = gateway?.lastConnectedAt;
  if (connectedAt == null || connectedAt <= 0) return '-';
  final duration = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(connectedAt),
  );
  if (duration.inDays > 0) return '${duration.inDays}d';
  if (duration.inHours > 0) return '${duration.inHours}h';
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '<1m';
}

String _formatTokens(int value) {
  final sign = value < 0 ? '-' : '';
  final n = value.abs();
  if (n >= 1000000) {
    final formatted = (n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1);
    return '$sign${_trimTrailingZero(formatted)}M';
  }
  if (n >= 1000) {
    final formatted = (n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1);
    return '$sign${_trimTrailingZero(formatted)}k';
  }
  return '$value';
}

String _trimTrailingZero(String value) {
  if (!value.contains('.')) return value;
  return value.replaceFirst(RegExp(r'\.0$'), '');
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}
