import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/services/skills_api_service.dart';

export 'package:client/providers/database_providers.dart'
    show skillCacheRepositoryProvider, skillsApiServiceProvider;

final skillsControllerProvider =
    StateNotifierProvider<SkillsController, SkillsState>((ref) {
      final locale = ref.watch(
        localeProvider.select((locale) => locale?.languageCode ?? 'en'),
      );
      return SkillsController(
        ref.watch(skillsApiServiceProvider),
        cache: ref.watch(skillCacheRepositoryProvider),
        locale: locale,
      );
    });

@immutable
class SkillsState {
  final List<ManagedSkill> skills;
  final List<SkillScope> scopes;
  final String? selectedScopeId;
  final ManagedSkill? selected;
  final bool isLoading;
  final bool isSaving;
  final Set<String> busySkillIds;
  final Set<String> togglingSkillIds;
  final String? errorMessage;
  final String? errorGatewayId;

  const SkillsState({
    this.skills = const [],
    this.scopes = const [],
    this.selectedScopeId,
    this.selected,
    this.isLoading = false,
    this.isSaving = false,
    this.busySkillIds = const <String>{},
    this.togglingSkillIds = const <String>{},
    this.errorMessage,
    this.errorGatewayId,
  });

  SkillScope? get selectedScope {
    for (final scope in scopes) {
      if (scope.id == selectedScopeId) return scope;
    }
    return null;
  }

  bool get isScopeReadOnly => selectedScope?.readonly == true;

  SkillsState copyWith({
    List<ManagedSkill>? skills,
    List<SkillScope>? scopes,
    String? selectedScopeId,
    bool clearSelectedScope = false,
    ManagedSkill? selected,
    bool clearSelected = false,
    bool? isLoading,
    bool? isSaving,
    Set<String>? busySkillIds,
    Set<String>? togglingSkillIds,
    String? errorMessage,
    String? errorGatewayId,
    bool clearError = false,
  }) {
    return SkillsState(
      skills: skills ?? this.skills,
      scopes: scopes ?? this.scopes,
      selectedScopeId: clearSelectedScope
          ? null
          : (selectedScopeId ?? this.selectedScopeId),
      selected: clearSelected ? null : (selected ?? this.selected),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      busySkillIds: busySkillIds ?? this.busySkillIds,
      togglingSkillIds: togglingSkillIds ?? this.togglingSkillIds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorGatewayId: clearError
          ? null
          : (errorGatewayId ?? this.errorGatewayId),
    );
  }
}

class SkillsController extends StateNotifier<SkillsState> {
  SkillsController(
    this._api, {
    SkillCacheRepository? cache,
    String locale = 'en',
  }) : _cache = cache,
       _locale = locale,
       super(const SkillsState());

  final SkillsApiService _api;
  final SkillCacheRepository? _cache;
  final String _locale;
  int _scopedListGeneration = 0;

  Future<void> load({bool force = false}) async {
    if (state.isLoading && !force) return;
    final requestGeneration = ++_scopedListGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final scopes = await _api.listScopes();
      if (requestGeneration != _scopedListGeneration) return;
      final selectedScope = _resolveInitialScope(scopes, state.selectedScopeId);
      await _loadScopedList(scopes, selectedScope);
    } catch (e) {
      if (requestGeneration != _scopedListGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _skillErrorMessage(e),
      );
    }
  }

  Future<void> syncGateways(List<GatewayInfo> gateways, {bool force = false}) {
    final scopes = gateways
        .where((gateway) => gateway.supports('skills'))
        .map(_scopeFromGateway)
        .toList();
    final selectedScope = _resolveInitialScope(scopes, state.selectedScopeId);
    final sameScopes = listEquals(
      scopes.map(_scopeSignature).toList(),
      state.scopes.map(_scopeSignature).toList(),
    );
    if (!force &&
        sameScopes &&
        selectedScope?.id == state.selectedScopeId &&
        state.skills.isNotEmpty) {
      state = state.copyWith(scopes: scopes);
      return Future.value();
    }
    return _loadScopedList(
      scopes,
      selectedScope,
      clearSkills: selectedScope?.id != state.selectedScopeId,
    );
  }

  Future<void> refresh() {
    final selectedScope = state.selectedScope;
    if (selectedScope == null) return load(force: true);
    return _loadScopedList(state.scopes, selectedScope);
  }

  void applyExternalRefresh(Map<String, List<ManagedSkill>> skillsByGateway) {
    final gatewayId = state.selectedScope?.gatewayId;
    if (gatewayId == null) return;
    final skills = skillsByGateway[gatewayId];
    if (skills == null) return;
    state = state.copyWith(skills: skills);
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  Future<void> selectScope(String scopeId) async {
    final scope = _findScope(scopeId);
    if (scope == null || scope.id == state.selectedScopeId) return;
    await _loadScopedList(state.scopes, scope, clearSkills: true);
  }

  Future<void> selectGateway(String gatewayId) async {
    for (final scope in state.scopes) {
      if (scope.gatewayId == gatewayId) {
        await selectScope(scope.id);
        return;
      }
    }
  }

  void selectUnavailableGateway(
    List<GatewayInfo> gateways,
    String gatewayId,
    String message,
  ) {
    final scopes = gateways
        .where((gateway) => gateway.supports('skills'))
        .map(_scopeFromGateway)
        .toList();
    final selectedScope = scopes
        .where((scope) => scope.gatewayId == gatewayId)
        .firstOrNull;
    if (selectedScope == null) return;
    _scopedListGeneration += 1;
    state = state.copyWith(
      scopes: scopes,
      selectedScopeId: selectedScope.id,
      skills: const [],
      isLoading: false,
      isSaving: false,
      busySkillIds: const <String>{},
      togglingSkillIds: const <String>{},
      clearSelected: true,
      errorMessage: message,
      errorGatewayId: gatewayId,
    );
  }

  Future<void> _loadScopedList(
    List<SkillScope> scopes,
    SkillScope? selectedScope, {
    bool clearSkills = false,
  }) async {
    if (selectedScope == null) {
      _scopedListGeneration += 1;
      state = state.copyWith(
        scopes: scopes,
        clearSelectedScope: true,
        skills: const [],
        isLoading: false,
      );
      return;
    }
    final requestScopeId = selectedScope.id;
    final requestGeneration = ++_scopedListGeneration;
    state = state.copyWith(
      scopes: scopes,
      selectedScopeId: requestScopeId,
      skills: clearSkills ? const [] : state.skills,
      isLoading: true,
      clearSelected: true,
      clearError: true,
    );
    try {
      final cache = _cache;
      if (cache != null) {
        final cached = await cache.getSkills(
          _scopeGatewayId(selectedScope),
          _locale,
        );
        if (requestGeneration != _scopedListGeneration) return;
        if (cached.isNotEmpty) {
          state = state.copyWith(skills: cached);
        }
      }
      final skills = await _syncSkills(selectedScope);
      if (requestGeneration != _scopedListGeneration) return;
      state = state.copyWith(skills: skills, isLoading: false);
    } catch (e) {
      if (requestGeneration != _scopedListGeneration) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: _skillErrorMessage(e, scope: selectedScope),
      );
    }
  }

  Future<ManagedSkill?> loadDetail(String id) async {
    final requestScope = state.selectedScope;
    final requestScopeId = state.selectedScopeId;
    _setSkillBusy(id, true, clearError: true);
    try {
      final skill = await _getCachedSkill(id, requestScope);
      if (state.selectedScopeId != requestScopeId) return null;
      if (skill == null) {
        state = state.copyWith(busySkillIds: _withoutBusy(id));
        return null;
      }
      state = state.copyWith(
        selected: skill,
        busySkillIds: _withoutBusy(id),
        skills: _replaceSkill(state.skills, skill),
      );
      return skill;
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: _skillErrorMessage(e, scope: state.selectedScope),
      );
      return null;
    }
  }

  Future<void> create(SkillDraft draft) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final skill = await _createSkill(draft, state.selectedScope);
      state = state.copyWith(
        isSaving: false,
        selected: skill,
        skills: [...state.skills, skill]..sort(_sortSkills),
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: _skillErrorMessage(e, scope: state.selectedScope),
      );
      rethrow;
    }
  }

  Future<void> update(String id, SkillDraft draft) async {
    _setSkillBusy(id, true, clearError: true);
    try {
      final skill = await _updateSkill(id, draft, state.selectedScope);
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        selected: skill,
        skills: _replaceSkill(state.skills, skill, previousId: id)
          ..sort(_sortSkills),
      );
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: _skillErrorMessage(e, scope: state.selectedScope),
      );
      rethrow;
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final before = state.skills;
    final currentIndex = before.indexWhere((skill) => skill.id == id);
    final current = currentIndex == -1 ? null : before[currentIndex];
    _setSkillToggling(id, true, clearError: true);
    if (current != null) {
      state = state.copyWith(
        skills: _replaceSkill(state.skills, current.copyWith(enabled: enabled)),
        selected: state.selected?.id == id
            ? state.selected!.copyWith(enabled: enabled)
            : state.selected,
      );
    }
    try {
      await _setSkillEnabled(id, enabled, state.selectedScope);
      state = state.copyWith(togglingSkillIds: _withoutToggling(id));
    } catch (e) {
      state = state.copyWith(
        skills: before,
        togglingSkillIds: _withoutToggling(id),
        errorMessage: _skillErrorMessage(e, scope: state.selectedScope),
      );
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    _setSkillBusy(id, true, clearError: true);
    try {
      await _deleteSkill(id, state.selectedScope);
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        clearSelected: state.selected?.id == id,
        skills: state.skills.where((skill) => skill.id != id).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: _skillErrorMessage(e, scope: state.selectedScope),
      );
      rethrow;
    }
  }

  void _setSkillBusy(String id, bool busy, {bool clearError = false}) {
    state = state.copyWith(
      busySkillIds: busy ? _withBusy(id) : _withoutBusy(id),
      clearError: clearError,
    );
  }

  Set<String> _withBusy(String id) => {...state.busySkillIds, id};

  Set<String> _withoutBusy(String id) => {...state.busySkillIds}..remove(id);

  void _setSkillToggling(String id, bool busy, {bool clearError = false}) {
    state = state.copyWith(
      togglingSkillIds: busy ? _withToggling(id) : _withoutToggling(id),
      clearError: clearError,
    );
  }

  Set<String> _withToggling(String id) => {...state.togglingSkillIds, id};

  Set<String> _withoutToggling(String id) =>
      {...state.togglingSkillIds}..remove(id);

  List<ManagedSkill> _replaceSkill(
    List<ManagedSkill> skills,
    ManagedSkill next, {
    String? previousId,
  }) {
    final items = previousId != null && previousId != next.id
        ? skills.where((skill) => skill.id != previousId).toList()
        : [...skills];
    final index = items.indexWhere((skill) => skill.id == next.id);
    if (index == -1) return [...items, next];
    return items..[index] = next;
  }

  static int _sortSkills(ManagedSkill a, ManagedSkill b) {
    return '${a.category}/${a.name}'.compareTo('${b.category}/${b.name}');
  }

  Future<List<ManagedSkill>> _syncSkills(SkillScope selectedScope) {
    final cache = _cache;
    if (cache == null) {
      return _api.listSkills(scope: selectedScope, locale: _locale);
    }
    return cache.syncGateway(selectedScope, _locale);
  }

  Future<ManagedSkill?> _getCachedSkill(String id, SkillScope? scope) {
    final cache = _cache;
    if (cache == null || scope == null) return Future.value();
    return cache.getCachedSkill(id, scope, _locale);
  }

  Future<ManagedSkill> _createSkill(SkillDraft draft, SkillScope? scope) {
    final cache = _cache;
    if (cache == null) {
      return _api.createSkill(draft, scope: scope, locale: _locale);
    }
    return cache.create(draft, scope, _locale);
  }

  Future<ManagedSkill> _updateSkill(
    String id,
    SkillDraft draft,
    SkillScope? scope,
  ) {
    final cache = _cache;
    if (cache == null) {
      return _api.updateSkill(id, draft, scope: scope, locale: _locale);
    }
    return cache.update(id, draft, scope, _locale);
  }

  Future<void> _setSkillEnabled(String id, bool enabled, SkillScope? scope) {
    final cache = _cache;
    if (cache == null) return _api.setEnabled(id, enabled, scope: scope);
    return cache.setEnabled(id, enabled, scope, _locale);
  }

  Future<void> _deleteSkill(String id, SkillScope? scope) {
    final cache = _cache;
    if (cache == null) return _api.deleteSkill(id, scope: scope);
    return cache.delete(id, scope);
  }

  SkillScope? _resolveInitialScope(
    List<SkillScope> scopes,
    String? currentScopeId,
  ) {
    if (scopes.isEmpty) return null;
    if (currentScopeId != null) {
      for (final scope in scopes) {
        if (scope.id == currentScopeId) return scope;
      }
    }
    for (final scope in scopes) {
      if (scope.isGateway) return scope;
    }
    return null;
  }

  SkillScope? _findScope(String scopeId) {
    for (final scope in state.scopes) {
      if (scope.id == scopeId) return scope;
    }
    return null;
  }
}

SkillScope _scopeFromGateway(GatewayInfo gateway) {
  return SkillScope(
    id: 'gateway:${gateway.gatewayId}',
    type: 'gateway',
    label: gateway.displayName,
    description: gateway.gatewayId,
    readonly: false,
    gatewayId: gateway.gatewayId,
  );
}

String _scopeGatewayId(SkillScope scope) {
  final gatewayId = scope.gatewayId;
  if (gatewayId != null && gatewayId.isNotEmpty) return gatewayId;
  return 'global';
}

String _scopeSignature(SkillScope scope) {
  return '${scope.id}:${scope.label}:${scope.description}:${scope.readonly}:${scope.gatewayId}';
}

String _skillErrorMessage(Object error, {SkillScope? scope}) {
  if (error is DioException) {
    final response = error.response;
    final statusCode = response?.statusCode;
    final code = _responseErrorCode(response?.data);
    final gatewayName = _gatewayDisplayName(scope?.gatewayId);

    if (statusCode == 504 || code == 'gateway_timeout') {
      return '$gatewayName 网关响应超时，请确认 $gatewayName Gateway 正在运行后重试。';
    }
    if (statusCode == 503 || code == 'gateway_unavailable') {
      return '$gatewayName Gateway 未连接，请先启动或重连 gateway。';
    }
    if (statusCode == 400 || code == 'gateway_required') {
      return '请选择一个已连接的 gateway 后再刷新技能。';
    }

    final serverMessage = _responseMessage(response?.data);
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return serverMessage;
    }
    if (statusCode != null) {
      return '技能请求失败，服务端返回 $statusCode。';
    }
    return '无法连接 Clawke Server，请检查服务是否正在运行。';
  }

  if (error is FormatException) {
    return '技能接口返回格式异常，请稍后重试。';
  }

  final message = error.toString();
  if (message.isEmpty) return '技能请求失败，请稍后重试。';
  return message;
}

String _gatewayDisplayName(String? gatewayId) {
  final value = gatewayId?.trim();
  if (value == null || value.isEmpty) return 'Gateway';
  final lower = value.toLowerCase();
  if (lower.contains('hermes')) return 'Hermes';
  if (lower.contains('openclaw')) return 'OpenClaw';
  return value;
}

String? _responseErrorCode(Object? data) {
  if (data is Map<String, dynamic>) return data['error'] as String?;
  if (data is Map) return data['error'] as String?;
  return null;
}

String? _responseMessage(Object? data) {
  if (data is Map<String, dynamic>) return data['message'] as String?;
  if (data is Map) return data['message'] as String?;
  return null;
}
