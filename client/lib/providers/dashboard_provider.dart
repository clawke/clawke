import 'package:client/models/gateway_info.dart';
import 'package:client/models/usage_dashboard.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/services/dashboard_api_service.dart';
import 'package:client/widgets/gateway_unavailable_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:client/providers/database_providers.dart'
    show dashboardApiServiceProvider;

const dashboardGatewayCapability = 'chat';

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>((ref) {
      return DashboardController(ref.watch(dashboardApiServiceProvider));
    });

@immutable
class DashboardState {
  final List<GatewayInfo> gateways;
  final String? selectedGatewayId;
  final UsageDashboard? dashboard;
  final bool isLoading;
  final String? errorMessage;
  final String? errorGatewayId;

  const DashboardState({
    this.gateways = const [],
    this.selectedGatewayId,
    this.dashboard,
    this.isLoading = false,
    this.errorMessage,
    this.errorGatewayId,
  });

  GatewayInfo? get selectedGateway {
    return gatewayById(gateways, selectedGatewayId);
  }

  DashboardState copyWith({
    List<GatewayInfo>? gateways,
    String? selectedGatewayId,
    bool clearSelectedGateway = false,
    UsageDashboard? dashboard,
    bool clearDashboard = false,
    bool? isLoading,
    String? errorMessage,
    String? errorGatewayId,
    bool clearError = false,
  }) {
    return DashboardState(
      gateways: gateways ?? this.gateways,
      selectedGatewayId: clearSelectedGateway
          ? null
          : (selectedGatewayId ?? this.selectedGatewayId),
      dashboard: clearDashboard ? null : (dashboard ?? this.dashboard),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorGatewayId: clearError
          ? null
          : (errorGatewayId ?? this.errorGatewayId),
    );
  }
}

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController(this._api) : super(const DashboardState());

  final DashboardApiService _api;
  int _loadGeneration = 0;

  Future<void> syncGateways(List<GatewayInfo> gateways) async {
    final ordered = orderGatewaysForSelection(
      gateways,
      dashboardGatewayCapability,
      currentGatewayId: state.selectedGatewayId,
    );
    final nextSelected = _resolveGateway(ordered, state.selectedGatewayId);
    final selectionChanged = nextSelected != state.selectedGatewayId;
    final sameGateways = listEquals(
      ordered.map(_gatewaySignature).toList(),
      state.gateways.map(_gatewaySignature).toList(),
    );

    if (sameGateways && nextSelected == state.selectedGatewayId) return;
    if (selectionChanged) _loadGeneration += 1;

    state = state.copyWith(
      gateways: ordered,
      selectedGatewayId: nextSelected,
      clearSelectedGateway: nextSelected == null,
      clearDashboard: selectionChanged,
      isLoading: selectionChanged ? false : state.isLoading,
      clearError: selectionChanged,
    );

    if (nextSelected != null) {
      await load(gatewayId: nextSelected, force: true);
    }
  }

  Future<void> load({String? gatewayId, bool force = false}) async {
    final selected = gatewayId ?? state.selectedGatewayId;
    if (selected == null) return;
    if (state.dashboard != null &&
        state.dashboard!.gatewayId == selected &&
        !force) {
      return;
    }

    final requestGatewayId = selected;
    final requestGeneration = ++_loadGeneration;
    state = state.copyWith(
      selectedGatewayId: requestGatewayId,
      clearDashboard: requestGatewayId != state.selectedGatewayId,
      isLoading: true,
      clearError: true,
    );

    try {
      final dashboard = await _api.getUsage(gatewayId: requestGatewayId);
      if (requestGeneration != _loadGeneration) return;
      state = state.copyWith(dashboard: dashboard, isLoading: false);
    } catch (error) {
      if (requestGeneration != _loadGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _dashboardErrorMessage(error),
        errorGatewayId: requestGatewayId,
      );
    }
  }

  Future<void> refresh() => load(force: true);

  Future<void> selectGateway(String gatewayId) async {
    if (gatewayId == state.selectedGatewayId) return;
    await load(gatewayId: gatewayId, force: true);
  }

  void selectUnavailableGateway(
    List<GatewayInfo> gateways,
    String gatewayId,
    String message, {
    bool showErrorMessage = true,
  }) {
    if (!gateways.any((gateway) => gateway.gatewayId == gatewayId)) return;
    _loadGeneration += 1;
    state = DashboardState(
      gateways: gateways,
      selectedGatewayId: gatewayId,
      isLoading: false,
      errorMessage: showErrorMessage ? message : null,
      errorGatewayId: gatewayId,
    );
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  String? _resolveGateway(List<GatewayInfo> gateways, String? currentId) {
    if (currentId != null &&
        gateways.any((gateway) => gateway.gatewayId == currentId)) {
      return currentId;
    }
    if (gateways.isEmpty) return null;
    final online = gateways.where(
      (gateway) =>
          gateway.status == GatewayConnectionStatus.online &&
          gateway.supports(dashboardGatewayCapability),
    );
    return (online.isEmpty ? gateways.first : online.first).gatewayId;
  }

  String _gatewaySignature(GatewayInfo gateway) {
    return [
      gateway.gatewayId,
      gateway.displayName,
      gateway.status.name,
      gateway.capabilities.join(','),
    ].join(':');
  }

  String _dashboardErrorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      if (status != null) return 'Dashboard request failed ($status)';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Dashboard request timed out';
      }
      return error.message ?? 'Dashboard request failed';
    }
    if (error is FormatException) return error.message;
    return error.toString();
  }
}
