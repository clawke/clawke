import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/skills_provider.dart';
import 'package:client/services/skills_api_service.dart';

class _FakeSkillsApiService extends SkillsApiService {
  _FakeSkillsApiService(this.items);

  List<ManagedSkill> items;
  List<SkillScope> scopes = const [
    SkillScope(
      id: 'library',
      type: 'library',
      label: 'Clawke Library',
      description: 'Central skills',
      readonly: false,
    ),
    SkillScope(
      id: 'all-gateways',
      type: 'all_gateways',
      label: 'All Gateways',
      description: 'Read-only overview',
      readonly: true,
    ),
  ];
  String? loadedScopeId;
  String? toggledId;
  bool? toggledEnabled;
  String? toggledScopeId;

  @override
  Future<List<SkillScope>> listScopes() async => scopes;

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async {
    loadedScopeId = scope?.id;
    return items;
  }

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) async {
    toggledId = id;
    toggledEnabled = enabled;
    toggledScopeId = scope?.id;
    final index = items.indexWhere((skill) => skill.id == id);
    final next = items[index].copyWith(enabled: enabled);
    items = [...items]..[index] = next;
  }
}

class _SlowFakeSkillsApiService extends SkillsApiService {
  _SlowFakeSkillsApiService(this.items);

  List<ManagedSkill> items;
  final completer = Completer<void>();

  @override
  Future<List<SkillScope>> listScopes() async => const [
    SkillScope(
      id: 'library',
      type: 'library',
      label: 'Clawke Library',
      description: 'Central skills',
      readonly: false,
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async => items;

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) {
    return completer.future;
  }
}

void main() {
  test('SkillsController loads skills and updates enabled state', () async {
    final fake = _FakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [skillsApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    expect(
      container.read(skillsControllerProvider).skills.single.enabled,
      true,
    );

    await container
        .read(skillsControllerProvider.notifier)
        .setEnabled('general/web-search', false);

    expect(fake.toggledId, 'general/web-search');
    expect(fake.toggledEnabled, false);
    expect(fake.toggledScopeId, 'library');
    expect(
      container.read(skillsControllerProvider).skills.single.enabled,
      false,
    );
  });

  test('SkillsController loads scopes and defaults to library scope', () async {
    final fake = _FakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [skillsApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();

    final state = container.read(skillsControllerProvider);
    expect(state.scopes.map((scope) => scope.id), contains('library'));
    expect(state.selectedScopeId, 'library');
    expect(state.selectedScope?.label, 'Clawke Library');
    expect(state.isScopeReadOnly, isFalse);
    expect(fake.loadedScopeId, 'library');
  });

  test(
    'SkillsController falls back to legacy skills list when scopes fail',
    () async {
      final fake = _FailingScopesSkillsApiService([
        const ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [skillsApiServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(skillsControllerProvider.notifier).load();

      final state = container.read(skillsControllerProvider);
      expect(state.skills.single.name, 'web-search');
      expect(state.scopes, isEmpty);
      expect(state.selectedScopeId, isNull);
      expect(fake.legacyListCalled, isTrue);
      expect(state.errorMessage, isNull);
    },
  );

  test(
    'SkillsController changes selected scope and reloads scoped skills',
    () async {
      final fake = _FakeSkillsApiService([
        const ManagedSkill(
          id: 'general/web-search',
          name: 'web-search',
          description: 'Search the web',
          category: 'general',
          enabled: true,
          source: 'managed',
          sourceLabel: 'Clawke managed',
          writable: true,
          deletable: true,
          path: 'general/web-search/SKILL.md',
          root: '/tmp/skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [skillsApiServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await container.read(skillsControllerProvider.notifier).load();
      await container
          .read(skillsControllerProvider.notifier)
          .selectScope('all-gateways');

      final state = container.read(skillsControllerProvider);
      expect(state.selectedScopeId, 'all-gateways');
      expect(state.isScopeReadOnly, isTrue);
      expect(fake.loadedScopeId, 'all-gateways');
    },
  );

  test('SkillsController updates enabled state before API completes', () async {
    final fake = _SlowFakeSkillsApiService([
      const ManagedSkill(
        id: 'general/web-search',
        name: 'web-search',
        description: 'Search the web',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/web-search/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [skillsApiServiceProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(skillsControllerProvider.notifier).load();
    unawaited(
      container
          .read(skillsControllerProvider.notifier)
          .setEnabled('general/web-search', false),
    );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(skillsControllerProvider);
    expect(state.skills.single.enabled, false);
    expect(state.togglingSkillIds, contains('general/web-search'));
  });
}

class _FailingScopesSkillsApiService extends SkillsApiService {
  _FailingScopesSkillsApiService(this.items);

  final List<ManagedSkill> items;
  bool legacyListCalled = false;

  @override
  Future<List<SkillScope>> listScopes() async {
    throw Exception('scopes unavailable');
  }

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async {
    legacyListCalled = scope == null;
    return items;
  }
}
