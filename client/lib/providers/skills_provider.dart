import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/services/skills_api_service.dart';

final skillsApiServiceProvider = Provider<SkillsApiService>((ref) {
  return SkillsApiService();
});

final skillsControllerProvider =
    StateNotifierProvider<SkillsController, SkillsState>((ref) {
      return SkillsController(ref.read(skillsApiServiceProvider));
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
    );
  }
}

class SkillsController extends StateNotifier<SkillsState> {
  SkillsController(this._api) : super(const SkillsState());

  final SkillsApiService _api;

  Future<void> load({bool force = false}) async {
    if (state.skills.isNotEmpty && !force) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final scopes = await _api.listScopes();
      final selectedScope = _resolveInitialScope(scopes, state.selectedScopeId);
      final skills = await _api.listSkills(scope: selectedScope);
      state = state.copyWith(
        scopes: scopes,
        selectedScopeId: selectedScope?.id,
        skills: skills,
        isLoading: false,
      );
    } catch (e) {
      try {
        final skills = await _api.listSkills();
        state = state.copyWith(
          scopes: const [],
          clearSelectedScope: true,
          skills: skills,
          isLoading: false,
        );
      } catch (fallbackError) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: fallbackError.toString(),
        );
      }
    }
  }

  Future<void> refresh() => load(force: true);

  Future<void> selectScope(String scopeId) async {
    final scope = _findScope(scopeId);
    if (scope == null || scope.id == state.selectedScopeId) return;
    state = state.copyWith(
      selectedScopeId: scope.id,
      isLoading: true,
      clearSelected: true,
      clearError: true,
    );
    try {
      final skills = await _api.listSkills(scope: scope);
      state = state.copyWith(skills: skills, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<ManagedSkill?> loadDetail(String id) async {
    _setSkillBusy(id, true, clearError: true);
    try {
      final skill = await _api.getSkill(id, scope: state.selectedScope);
      state = state.copyWith(
        selected: skill,
        busySkillIds: _withoutBusy(id),
        skills: _replaceSkill(state.skills, skill),
      );
      return skill;
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  Future<void> create(SkillDraft draft) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final skill = await _api.createSkill(draft);
      state = state.copyWith(
        isSaving: false,
        selected: skill,
        skills: [...state.skills, skill]..sort(_sortSkills),
      );
    } catch (e) {
      state = state.copyWith(isSaving: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> update(String id, SkillDraft draft) async {
    _setSkillBusy(id, true, clearError: true);
    try {
      final skill = await _api.updateSkill(
        id,
        draft,
        scope: state.selectedScope,
      );
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        selected: skill,
        skills: _replaceSkill(state.skills, skill)..sort(_sortSkills),
      );
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: e.toString(),
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
      await _api.setEnabled(id, enabled, scope: state.selectedScope);
      state = state.copyWith(togglingSkillIds: _withoutToggling(id));
    } catch (e) {
      state = state.copyWith(
        skills: before,
        togglingSkillIds: _withoutToggling(id),
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    _setSkillBusy(id, true, clearError: true);
    try {
      await _api.deleteSkill(id, scope: state.selectedScope);
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        clearSelected: state.selected?.id == id,
        skills: state.skills.where((skill) => skill.id != id).toList(),
      );
    } catch (e) {
      state = state.copyWith(
        busySkillIds: _withoutBusy(id),
        errorMessage: e.toString(),
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
    ManagedSkill next,
  ) {
    final index = skills.indexWhere((skill) => skill.id == next.id);
    if (index == -1) return [...skills, next];
    return [...skills]..[index] = next;
  }

  static int _sortSkills(ManagedSkill a, ManagedSkill b) {
    return '${a.category}/${a.name}'.compareTo('${b.category}/${b.name}');
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
      if (scope.id == 'library') return scope;
    }
    return scopes.first;
  }

  SkillScope? _findScope(String scopeId) {
    for (final scope in state.scopes) {
      if (scope.id == scopeId) return scope;
    }
    return null;
  }
}
