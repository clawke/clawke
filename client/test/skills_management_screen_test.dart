import 'dart:async';

import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/skills_provider.dart';
import 'package:client/screens/skills_management_screen.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSkillsApiService extends SkillsApiService {
  SkillDraft? createdDraft;
  String? updatedId;
  SkillDraft? updatedDraft;
  String? updatedScopeId;
  String? deletedId;
  String? deletedScopeId;
  String? toggledId;
  bool? toggledEnabled;
  String? toggledScopeId;
  String? detailId;
  String? detailScopeId;

  static const webSearch = ManagedSkill(
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
  );

  static const deployHelper = ManagedSkill(
    id: 'ops/deploy-helper',
    name: 'deploy-helper',
    description: 'Prepare deployments',
    category: 'ops',
    enabled: false,
    source: 'external',
    sourceLabel: 'Hermes skills',
    writable: true,
    deletable: false,
    path: 'ops/deploy-helper/SKILL.md',
    root: '/tmp/hermes-skills',
    updatedAt: 0,
    hasConflict: false,
  );

  @override
  Future<List<SkillScope>> listScopes() async => const [
    SkillScope(
      id: 'library',
      type: 'library',
      label: 'Clawke Library',
      description: 'Central skills',
      readonly: false,
    ),
    SkillScope(
      id: 'hermes-work',
      type: 'gateway',
      label: 'Gateway: hermes-work',
      description: 'Hermes Work',
      readonly: false,
      gatewayId: 'hermes-work',
    ),
    SkillScope(
      id: 'all-gateways',
      type: 'all_gateways',
      label: 'All Gateways',
      description: 'Read-only overview',
      readonly: true,
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async => [
    webSearch,
    deployHelper,
  ];

  @override
  Future<ManagedSkill> getSkill(String id, {SkillScope? scope}) async {
    detailId = id;
    detailScopeId = scope?.id;
    return switch (id) {
      'general/web-search' => webSearch.copyWith(
        trigger: 'Use when web lookup is needed',
        body: '## Existing body\n',
      ),
      'ops/deploy-helper' => deployHelper.copyWith(
        trigger: 'Use before deployment',
        body: '## Deploy body\n',
      ),
      _ => throw StateError('Unknown skill: $id'),
    };
  }

  @override
  Future<ManagedSkill> createSkill(SkillDraft draft) async {
    createdDraft = draft;
    return ManagedSkill(
      id: '${draft.category}/${draft.name}',
      name: draft.name,
      description: draft.description,
      category: draft.category,
      trigger: draft.trigger,
      body: draft.body,
      enabled: true,
      source: 'managed',
      sourceLabel: 'Clawke managed',
      writable: true,
      deletable: true,
      path: '${draft.category}/${draft.name}/SKILL.md',
      root: '/tmp/skills',
      updatedAt: 0,
      hasConflict: false,
    );
  }

  @override
  Future<ManagedSkill> updateSkill(
    String id,
    SkillDraft draft, {
    SkillScope? scope,
  }) async {
    updatedId = id;
    updatedDraft = draft;
    updatedScopeId = scope?.id;
    return ManagedSkill(
      id: '${draft.category}/${draft.name}',
      name: draft.name,
      description: draft.description,
      category: draft.category,
      trigger: draft.trigger,
      body: draft.body,
      enabled: id == webSearch.id ? webSearch.enabled : deployHelper.enabled,
      source: id == webSearch.id ? webSearch.source : deployHelper.source,
      sourceLabel: id == webSearch.id
          ? webSearch.sourceLabel
          : deployHelper.sourceLabel,
      writable: true,
      deletable: id == webSearch.id,
      path: '${draft.category}/${draft.name}/SKILL.md',
      root: id == webSearch.id ? webSearch.root : deployHelper.root,
      updatedAt: 0,
      hasConflict: false,
    );
  }

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) async {
    toggledId = id;
    toggledEnabled = enabled;
    toggledScopeId = scope?.id;
  }

  @override
  Future<void> deleteSkill(String id, {SkillScope? scope}) async {
    deletedId = id;
    deletedScopeId = scope?.id;
  }
}

class _SlowSkillsApiService extends _FakeSkillsApiService {
  final toggleCompleter = Completer<void>();
  final detailCompleter = Completer<ManagedSkill>();

  @override
  Future<void> setEnabled(String id, bool enabled, {SkillScope? scope}) {
    toggledId = id;
    toggledEnabled = enabled;
    toggledScopeId = scope?.id;
    return toggleCompleter.future;
  }

  @override
  Future<ManagedSkill> getSkill(String id, {SkillScope? scope}) {
    detailId = id;
    detailScopeId = scope?.id;
    return detailCompleter.future;
  }
}

class _ScopeAwareSkillsApiService extends _FakeSkillsApiService {
  final loadedScopes = <String?>[];

  @override
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async {
    loadedScopes.add(scope?.id);
    if (scope?.id == 'hermes-work') {
      return const [
        ManagedSkill(
          id: 'gateway/hermes-only',
          name: 'hermes-only',
          description: 'Only visible in Hermes',
          category: 'gateway',
          enabled: true,
          source: 'external',
          sourceLabel: 'Hermes skills',
          writable: true,
          deletable: false,
          path: 'gateway/hermes-only/SKILL.md',
          root: '/tmp/hermes-skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ];
    }
    if (scope?.id == 'all-gateways') {
      return const [
        ManagedSkill(
          id: 'overview/readonly-skill',
          name: 'readonly-skill',
          description: 'Read-only overview skill',
          category: 'overview',
          enabled: true,
          source: 'readonly',
          sourceLabel: 'All gateways',
          writable: false,
          deletable: false,
          path: 'overview/readonly-skill/SKILL.md',
          root: '/tmp/readonly',
          updatedAt: 0,
          hasConflict: false,
        ),
      ];
    }
    return super.listSkills(scope: scope);
  }
}

class _ManySkillsApiService extends SkillsApiService {
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
  Future<List<ManagedSkill>> listSkills({SkillScope? scope}) async => [
    for (var index = 0; index < 120; index++)
      ManagedSkill(
        id: 'general/skill-$index',
        name: 'skill-$index',
        description: 'Generated skill $index',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'Clawke managed',
        writable: true,
        deletable: true,
        path: 'general/skill-$index/SKILL.md',
        root: '/tmp/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
  ];
}

void main() {
  Widget buildSubject({Locale? locale, SkillsApiService? api}) {
    return ProviderScope(
      overrides: [
        skillsApiServiceProvider.overrideWithValue(
          api ?? _FakeSkillsApiService(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SkillsManagementScreen()),
      ),
    );
  }

  testWidgets('SkillsManagementScreen renders, filters, and opens editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    expect(find.text('web-search'), findsOneWidget);
    expect(find.text('deploy-helper'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'deploy');
    await tester.pumpAndSettle();

    expect(find.text('web-search'), findsNothing);
    expect(find.text('deploy-helper'), findsOneWidget);

    await tester.tap(find.text('新建技能'));
    await tester.pumpAndSettle();

    expect(find.text('新建技能'), findsWidgets);
    expect(find.text('SKILL.md 正文'), findsOneWidget);
    expect(
      find.textContaining('Describe what this skill does'),
      findsOneWidget,
    );
  });

  testWidgets('SkillsManagementScreen uses English labels in English locale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('New Skill'), findsOneWidget);
    expect(find.text('All'), findsWidgets);
    expect(find.text('Enabled'), findsWidgets);
    expect(find.text('Managed'), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Delete'), findsWidgets);

    expect(find.text('新建技能'), findsNothing);
    expect(find.text('全部来源'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsNothing);

    await tester.tap(find.text('New Skill'));
    await tester.pumpAndSettle();

    expect(find.text('New Skill'), findsWidgets);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('SKILL.md Body'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    expect(find.text('名称'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.text('描述'), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets(
    'desktop shows scope sidebar and disables actions for read-only scope',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildSubject(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('Clawke Library'), findsOneWidget);
      expect(find.text('Gateway: hermes-work'), findsOneWidget);
      expect(find.text('All Gateways'), findsOneWidget);

      await tester.tap(find.text('All Gateways'));
      await tester.pumpAndSettle();

      final newSkillButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'New Skill'),
      );
      expect(newSkillButton.onPressed, isNull);
      for (final editButton in tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Edit'),
      )) {
        expect(editButton.onPressed, isNull);
      }
      for (final deleteButton in tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Delete'),
      )) {
        expect(deleteButton.onPressed, isNull);
      }
      for (final toggle in tester.widgetList<Switch>(find.byType(Switch))) {
        expect(toggle.onChanged, isNull);
      }
    },
  );

  testWidgets('mobile shows top scope selector and bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(OutlinedButton, 'Clawke Library'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clawke Library'));
    await tester.pumpAndSettle();

    expect(find.text('Gateway: hermes-work'), findsOneWidget);
    expect(find.text('All Gateways'), findsOneWidget);
  });

  testWidgets('desktop scope switching reloads skills for selected gateway', (
    tester,
  ) async {
    final api = _ScopeAwareSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    expect(find.text('web-search'), findsOneWidget);
    expect(find.text('hermes-only'), findsNothing);

    await tester.tap(find.text('Gateway: hermes-work'));
    await tester.pumpAndSettle();

    expect(api.loadedScopes, ['library', 'hermes-work']);
    expect(find.text('web-search'), findsNothing);
    expect(find.text('hermes-only'), findsOneWidget);
  });

  testWidgets('mobile scope selection reloads gateway skills', (tester) async {
    final api = _ScopeAwareSkillsApiService();
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clawke Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gateway: hermes-work'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(OutlinedButton, 'Gateway: hermes-work'),
      findsOneWidget,
    );
    expect(find.text('web-search'), findsNothing);
    expect(find.text('hermes-only'), findsOneWidget);
  });

  testWidgets('creating a skill submits the SKILL.md draft and adds the row', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Skill'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'qa-helper');
    await tester.enterText(fields.at(1), 'testing');
    await tester.enterText(fields.at(2), 'Use when testing Skills UI');
    await tester.enterText(fields.at(3), 'Helps validate UI behavior');
    await tester.enterText(fields.at(4), '## Purpose\n\nValidate Skills UI.\n');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.createdDraft?.name, 'qa-helper');
    expect(api.createdDraft?.category, 'testing');
    expect(api.createdDraft?.description, 'Helps validate UI behavior');
    expect(api.createdDraft?.body, contains('Validate Skills UI'));
    expect(find.text('qa-helper'), findsOneWidget);
  });

  testWidgets('editing a skill loads detail and updates only that skill', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), 'Updated search description');
    await tester.enterText(fields.at(4), '## Updated body\n');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.detailId, 'general/web-search');
    expect(api.detailScopeId, 'library');
    expect(api.updatedId, 'general/web-search');
    expect(api.updatedScopeId, 'library');
    expect(api.updatedDraft?.description, 'Updated search description');
    expect(find.text('Updated search description'), findsOneWidget);
    expect(find.text('deploy-helper'), findsOneWidget);
  });

  testWidgets('canceling managed disable leaves the skill enabled', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Disable managed skill?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(api.toggledId, isNull);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
  });

  testWidgets('confirming managed disable toggles only that skill', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disabled'));
    await tester.pumpAndSettle();

    expect(api.toggledId, 'general/web-search');
    expect(api.toggledEnabled, isFalse);
    expect(api.toggledScopeId, 'library');
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isFalse);
    expect(switches[1].value, isFalse);
  });

  testWidgets('toggling one skill only disables that skill row', (
    tester,
  ) async {
    final api = _SlowSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disabled'));
    await tester.pump();

    expect(api.toggledId, 'general/web-search');
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    expect(switches[0].onChanged, isNull);
    expect(switches[1].onChanged, isNotNull);
  });

  testWidgets('toggling one skill keeps edit actions available', (
    tester,
  ) async {
    final api = _SlowSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disabled'));
    await tester.pump();

    expect(api.toggledId, 'general/web-search');
    final editButtons = tester
        .widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit'))
        .toList();
    expect(editButtons, hasLength(2));
    expect(editButtons[0].onPressed, isNotNull);
    expect(editButtons[1].onPressed, isNotNull);
  });

  testWidgets('editing one skill only disables that skill row', (tester) async {
    final api = _SlowSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
    await tester.pump();

    expect(api.detailId, 'general/web-search');
    final editButtons = tester
        .widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit'))
        .toList();
    expect(editButtons, hasLength(2));
    expect(editButtons[0].onPressed, isNull);
    expect(editButtons[1].onPressed, isNotNull);
  });

  testWidgets('SkillsManagementScreen lazily builds offscreen skill rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(locale: const Locale('en'), api: _ManySkillsApiService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('skill-0'), findsOneWidget);
    expect(find.text('skill-119'), findsNothing);
  });
}
