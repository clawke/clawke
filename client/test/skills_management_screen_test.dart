import 'dart:async';

import 'package:client/data/repositories/gateway_repository.dart';
import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/screens/skills_management_screen.dart';
import 'package:client/services/skills_api_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _hermesGateway = GatewayInfo(
  gatewayId: 'hermes-work',
  displayName: 'hermes-work',
  gatewayType: 'hermes',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

const _openClawGateway = GatewayInfo(
  gatewayId: 'openclaw-lab',
  displayName: 'openclaw-lab',
  gatewayType: 'openclaw',
  status: GatewayConnectionStatus.online,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

const _disconnectedOpenClawGateway = GatewayInfo(
  gatewayId: 'openclaw-lab',
  displayName: 'openclaw-lab',
  gatewayType: 'openclaw',
  status: GatewayConnectionStatus.disconnected,
  capabilities: ['chat', 'tasks', 'skills', 'models'],
);

class _FakeGatewayRepository implements GatewayRepository {
  _FakeGatewayRepository(this.gateways);

  final List<GatewayInfo> gateways;
  int syncCount = 0;
  final renamed = <String, String>{};

  @override
  Stream<List<GatewayInfo>> watchAll() => Stream.value(gateways);

  @override
  Stream<List<GatewayInfo>> watchOnline() => Stream.value(gateways);

  @override
  Future<List<GatewayInfo>> getOnlineGateways() async => gateways;

  @override
  Future<void> syncFromServer() async {
    syncCount += 1;
  }

  @override
  Future<void> markOnline(GatewayInfo gateway) async {}

  @override
  Future<void> markOffline(String gatewayId) async {}

  @override
  Future<void> renameGateway(String gatewayId, String displayName) async {
    renamed[gatewayId] = displayName;
  }
}

class _ApiBackedSkillCacheRepository implements SkillCacheRepository {
  _ApiBackedSkillCacheRepository(this.api);

  final SkillsApiService api;
  List<ManagedSkill> cached = const [];

  @override
  Stream<List<ManagedSkill>> watchSkills(String gatewayId, String locale) {
    return Stream.value(const []);
  }

  @override
  Future<List<ManagedSkill>> getSkills(String gatewayId, String locale) async {
    return const [];
  }

  @override
  Future<List<ManagedSkill>> syncGateway(
    SkillScope scope,
    String locale,
  ) async {
    final skills = await api.listSkills(scope: scope, locale: locale);
    cached = skills;
    return skills;
  }

  @override
  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    return cached.where((skill) => skill.id == id).firstOrNull;
  }

  @override
  Future<ManagedSkill?> getDetail(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    final skill = await api.getSkill(id, scope: scope, locale: locale);
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await api.createSkill(draft, scope: scope, locale: locale);
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) async {
    final skill = await api.updateSkill(
      id,
      draft,
      scope: scope,
      locale: locale,
    );
    cached = _replaceCached(skill);
    return skill;
  }

  @override
  Future<void> delete(String id, SkillScope? scope) async {
    await api.deleteSkill(id, scope: scope);
    cached = cached.where((skill) => skill.id != id).toList();
  }

  @override
  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) async {
    await api.setEnabled(id, enabled, scope: scope);
    final index = cached.indexWhere((skill) => skill.id == id);
    if (index != -1) {
      cached = [...cached]..[index] = cached[index].copyWith(enabled: enabled);
    }
  }

  List<ManagedSkill> _replaceCached(ManagedSkill skill) {
    return [...cached.where((item) => item.id != skill.id), skill];
  }
}

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
  String? createdScopeId;

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
      id: 'gateway:hermes-work',
      type: 'gateway',
      label: 'hermes-work',
      description: 'Hermes gateway',
      readonly: false,
      gatewayId: 'hermes-work',
    ),
    SkillScope(
      id: 'gateway:openclaw-lab',
      type: 'gateway',
      label: 'openclaw-lab',
      description: 'OpenClaw gateway',
      readonly: false,
      gatewayId: 'openclaw-lab',
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async => [webSearch, deployHelper];

  @override
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) async {
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
  Future<ManagedSkill> createSkill(
    SkillDraft draft, {
    SkillScope? scope,
    String? locale,
  }) async {
    createdDraft = draft;
    createdScopeId = scope?.id;
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
    String? locale,
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

class _EmptySkillsApiService extends _FakeSkillsApiService {
  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    return const [];
  }
}

class _ReadonlySkillApiService extends _FakeSkillsApiService {
  static final readonlySkill = _FakeSkillsApiService.webSearch.copyWith(
    writable: false,
    source: 'readonly',
    sourceLabel: 'Read-only skills',
  );

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async => [readonlySkill];

  @override
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) async {
    detailId = id;
    detailScopeId = scope?.id;
    return readonlySkill.copyWith(
      trigger: 'Use when web lookup is needed',
      body: '## Existing body\n',
    );
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
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) {
    detailId = id;
    detailScopeId = scope?.id;
    return detailCompleter.future;
  }
}

class _ScopeAwareSkillsApiService extends _FakeSkillsApiService {
  final loadedScopes = <String?>[];

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    loadedScopes.add(scope?.id);
    if (scope?.id == 'gateway:openclaw-lab') {
      return const [
        ManagedSkill(
          id: 'gateway/openclaw-only',
          name: 'openclaw-only',
          description: 'Only visible in OpenClaw',
          category: 'gateway',
          enabled: true,
          source: 'external',
          sourceLabel: 'OpenClaw skills',
          writable: true,
          deletable: false,
          path: 'gateway/openclaw-only/SKILL.md',
          root: '/tmp/openclaw-skills',
          updatedAt: 0,
          hasConflict: false,
        ),
      ];
    }
    return super.listSkills(scope: scope);
  }
}

class _CountingSkillsApiService extends _FakeSkillsApiService {
  int listCalls = 0;

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    listCalls += 1;
    return super.listSkills(scope: scope, locale: locale);
  }
}

class _ManySkillsApiService extends SkillsApiService {
  @override
  Future<List<SkillScope>> listScopes() async => const [
    SkillScope(
      id: 'gateway:hermes-work',
      type: 'gateway',
      label: 'hermes-work',
      description: 'Hermes gateway',
      readonly: false,
      gatewayId: 'hermes-work',
    ),
  ];

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async => [
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

class _GatewayOnlySkillsApiService extends _FakeSkillsApiService {
  @override
  Future<List<SkillScope>> listScopes() async {
    throw StateError('skills screen must use cached gateways');
  }
}

class _UnavailableSkillsApiService extends _FakeSkillsApiService {
  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/skills'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/skills'),
        statusCode: 503,
        data: const {'error': 'gateway_unavailable'},
      ),
      type: DioExceptionType.badResponse,
    );
  }
}

class _LocalizedSkillsApiService extends _FakeSkillsApiService {
  static const localizedWebSearch = ManagedSkill(
    id: 'general/web-search',
    name: 'web-search',
    description: 'Search the web',
    category: 'general',
    trigger: 'Use when web lookup is needed',
    body: '## Source body\n',
    enabled: true,
    source: 'managed',
    sourceLabel: 'Clawke managed',
    writable: true,
    deletable: true,
    path: 'general/web-search/SKILL.md',
    root: '/tmp/skills',
    updatedAt: 0,
    hasConflict: false,
    sourceHash: 'sha256:a',
    localizationLocale: 'zh-CN',
    localizationStatus: 'ready',
    translatedName: '网页搜索',
    translatedDescription: '搜索网页',
    translatedTrigger: '需要联网搜索时使用',
    translatedBody: '## 翻译正文\n',
  );

  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    return const [localizedWebSearch];
  }

  @override
  Future<ManagedSkill> getSkill(
    String id, {
    SkillScope? scope,
    String? locale,
  }) async {
    detailId = id;
    detailScopeId = scope?.id;
    return localizedWebSearch;
  }
}

class _OverflowStressSkillsApiService extends _FakeSkillsApiService {
  @override
  Future<List<ManagedSkill>> listSkills({
    SkillScope? scope,
    String? locale,
  }) async {
    return const [
      ManagedSkill(
        id: 'builtin/1password',
        name: '1password',
        description:
            '设置和使用 1Password CLI。适用于安装 CLI、启用桌面应用集成、登录多个账号，以及通过 op 读取、注入或运行秘密时使用。',
        category: 'general',
        enabled: true,
        source: 'managed',
        sourceLabel: 'OpenClaw built-in skills',
        writable: false,
        deletable: false,
        path:
            '/Users/samy/MyProject/ai/clawke_extends/openclaw/skills/1password/SKILL.md',
        root: '/Users/samy/MyProject/ai/clawke_extends/openclaw/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
      ManagedSkill(
        id: 'external/algorithmic-art',
        name: 'algorithmic-art',
        description: '使用 p5.js 创建算法艺术，采用种子随机性和交互式参数探索。适合生成艺术、算法艺术、流场、粒子系统时使用。',
        category: 'general',
        enabled: false,
        source: 'external',
        sourceLabel: 'OpenClaw agents-skills-personal',
        writable: true,
        deletable: true,
        path: '/Users/samy/.agents/skills/algorithmic-art/SKILL.md',
        root: '/Users/samy/.agents/skills',
        updatedAt: 0,
        hasConflict: false,
      ),
    ];
  }
}

void main() {
  Widget buildSubject({
    Locale? locale,
    SkillsApiService? api,
    List<GatewayInfo> gateways = const [_hermesGateway, _openClawGateway],
    ThemeData? theme,
    Widget child = const SkillsManagementScreen(),
  }) {
    final repository = _FakeGatewayRepository(gateways);
    final skillsApi = api ?? _FakeSkillsApiService();
    return ProviderScope(
      overrides: [
        skillsApiServiceProvider.overrideWithValue(skillsApi),
        skillCacheRepositoryProvider.overrideWithValue(
          _ApiBackedSkillCacheRepository(skillsApi),
        ),
        gatewayRepositoryProvider.overrideWithValue(repository),
        gatewayListProvider.overrideWith((ref) => Stream.value(gateways)),
      ],
      child: MaterialApp(
        theme: theme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('skills page title uses titleLarge text style', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('zh'),
        theme: ThemeData(
          textTheme: const TextTheme(
            titleLarge: TextStyle(fontSize: 25),
            headlineSmall: TextStyle(fontSize: 27),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester
        .widgetList<Text>(find.text('技能中心'))
        .singleWhere((widget) => widget.style?.fontWeight == FontWeight.w700);
    expect(title.style?.fontSize, 25);
  });

  testWidgets('skills page uses compact typography below the header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('en'),
        theme: ThemeData(
          useMaterial3: true,
          textTheme: const TextTheme(
            titleLarge: TextStyle(fontSize: 25),
            titleMedium: TextStyle(fontSize: 18),
            titleSmall: TextStyle(fontSize: 16),
            bodyLarge: TextStyle(fontSize: 18),
            bodyMedium: TextStyle(fontSize: 16),
            bodySmall: TextStyle(fontSize: 14),
            labelLarge: TextStyle(fontSize: 16),
            labelMedium: TextStyle(fontSize: 14),
            labelSmall: TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester
        .widgetList<Text>(find.text('Skills'))
        .singleWhere((widget) => widget.style?.fontWeight == FontWeight.w700);
    expect(title.style?.fontSize, 25);

    final searchField = tester.widget<TextField>(find.byType(TextField).first);
    expect(searchField.style?.fontSize, 16);
    expect(searchField.decoration?.hintStyle?.fontSize, 16);

    final dynamic statusFilter = tester.widget(
      find.byKey(const ValueKey('skills_status_filter')),
    );
    expect(
      statusFilter.style?.textStyle?.resolve(<WidgetState>{})?.fontSize,
      14,
    );

    final skillName = tester.widget<Text>(find.text('web-search'));
    expect(skillName.style?.fontSize, 16);
    final description = tester.widget<Text>(find.text('Search the web'));
    expect(description.style?.fontSize, 14);
    final sourceTag = tester.widget<Text>(find.text('Clawke managed').first);
    expect(sourceTag.style?.fontSize, 13);

    final editButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Edit').first,
    );
    expect(editButton.style?.textStyle?.resolve(<WidgetState>{})?.fontSize, 14);

    final pathText = tester.widget<Text>(
      find.byKey(const ValueKey('skill_card_path_general/web-search')),
    );
    expect(pathText.style?.fontSize, 14);
  });

  testWidgets('desktop stats are merged into status filters', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en')));
    await tester.pumpAndSettle();

    final dynamic statusFilter = tester.widget(
      find.byKey(const ValueKey('skills_status_filter')),
    );

    expect((statusFilter.segments[0].label as Text).data, 'All 2');
    expect((statusFilter.segments[1].label as Text).data, 'Enabled 1');
    expect((statusFilter.segments[2].label as Text).data, 'Disabled 1');
    expect(find.byKey(const ValueKey('skills_metric_all')), findsNothing);
    expect(find.byKey(const ValueKey('skills_metric_enabled')), findsNothing);
  });

  testWidgets('wide desktop uses two-column layout-c skill cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2048, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en')));
    await tester.pumpAndSettle();

    final firstCard = find.byKey(
      const ValueKey('skill_card_general/web-search'),
    );
    final secondCard = find.byKey(
      const ValueKey('skill_card_ops/deploy-helper'),
    );
    expect(firstCard, findsOneWidget);
    expect(secondCard, findsOneWidget);

    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    expect(firstRect.top, moreOrLessEquals(secondRect.top, epsilon: 1));
    expect(secondRect.left, greaterThan(firstRect.right));
    expect(firstRect.height, lessThanOrEqualTo(230));

    expect(
      tester.getSize(
        find.byKey(const ValueKey('skill_card_icon_general/web-search')),
      ),
      const Size(52, 52),
    );

    final description = tester.widget<Text>(
      find.byKey(const ValueKey('skill_card_description_general/web-search')),
    );
    expect(description.maxLines, 3);
    expect(description.overflow, TextOverflow.ellipsis);

    final path = tester.widget<Text>(
      find.byKey(const ValueKey('skill_card_path_general/web-search')),
    );
    expect(path.maxLines, 1);
    expect(path.overflow, TextOverflow.ellipsis);

    final controlsRect = tester.getRect(
      find.byKey(const ValueKey('skill_card_controls_general/web-search')),
    );
    expect(controlsRect.left, greaterThan(firstRect.center.dx));
    expect(find.text('Clawke managed'), findsOneWidget);
    expect(find.text('Hermes skills'), findsOneWidget);
    expect(find.text('Built-in skill'), findsNothing);
    expect(find.text('External skill'), findsNothing);
    expect(find.text('Read-only source'), findsNothing);
  });

  testWidgets('wide skill cards do not overflow with long labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('zh'),
        api: _OverflowStressSkillsApiService(),
        theme: ThemeData(
          textTheme: const TextTheme(
            titleSmall: TextStyle(fontSize: 24),
            bodySmall: TextStyle(fontSize: 20),
            labelSmall: TextStyle(fontSize: 19),
            labelMedium: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getRect(
            find.byKey(
              const ValueKey('skill_card_controls_external/algorithmic-art'),
            ),
          )
          .bottom,
      lessThanOrEqualTo(
        tester
            .getRect(
              find.byKey(const ValueKey('skill_card_external/algorithmic-art')),
            )
            .bottom,
      ),
    );
  });

  testWidgets('two-column wrapped-control skill cards keep compact height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    final firstCard = find.byKey(
      const ValueKey('skill_card_general/web-search'),
    );
    final secondCard = find.byKey(
      const ValueKey('skill_card_ops/deploy-helper'),
    );
    expect(firstCard, findsOneWidget);
    expect(secondCard, findsOneWidget);

    final firstRect = tester.getRect(firstCard);
    final secondRect = tester.getRect(secondCard);
    expect(firstRect.top, moreOrLessEquals(secondRect.top, epsilon: 1));
    expect(firstRect.height, lessThanOrEqualTo(240));
  });

  testWidgets('narrow skill card moves controls to bottom right row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en')));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('skill_card_general/web-search'));
    final body = find.byKey(
      const ValueKey('skill_card_body_general/web-search'),
    );
    final controls = find.byKey(
      const ValueKey('skill_card_controls_general/web-search'),
    );
    final status = find.byKey(
      const ValueKey('skill_card_status_general/web-search'),
    );
    final actions = find.byKey(
      const ValueKey('skill_card_actions_general/web-search'),
    );

    final cardRect = tester.getRect(card);
    final bodyRect = tester.getRect(body);
    final controlsRect = tester.getRect(controls);
    final statusRect = tester.getRect(status);
    final actionsRect = tester.getRect(actions);

    expect(controlsRect.top, greaterThan(bodyRect.bottom));
    expect(
      controlsRect.right,
      moreOrLessEquals(cardRect.right - 18, epsilon: 1),
    );
    expect(
      statusRect.center.dy,
      moreOrLessEquals(actionsRect.center.dy, epsilon: 1),
    );
  });

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
    expect(
      find.text('/tmp/skills/general/web-search/SKILL.md'),
      findsOneWidget,
    );
    expect(find.text('general/web-search/SKILL.md'), findsNothing);

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
    expect(find.text('All 2'), findsOneWidget);
    expect(find.text('Enabled 1'), findsOneWidget);
    expect(find.text('Managed'), findsOneWidget);
    expect(find.text('External'), findsOneWidget);
    expect(find.text('Edit'), findsWidgets);
    expect(find.text('Details'), findsNothing);
    expect(find.text('Delete'), findsWidgets);

    expect(find.text('新建技能'), findsNothing);
    expect(find.text('全部来源'), findsNothing);
    expect(find.text('编辑'), findsNothing);
    expect(find.text('删除'), findsNothing);

    await tester.tap(find.text('New Skill'));
    await tester.pumpAndSettle();

    expect(find.text('New Skill'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('SKILL.md Body'), findsOneWidget);
    expect(find.text('Basic Info'), findsOneWidget);
    expect(find.textContaining('Required'), findsOneWidget);
    expect(find.textContaining('Created path'), findsOneWidget);
    expect(find.textContaining('Use When'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Create'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(
      find.text('Save changes to the selected gateway first.'),
      findsNothing,
    );

    expect(find.text('名称'), findsNothing);
    expect(find.text('分类'), findsNothing);
    expect(find.text('描述'), findsNothing);
    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('tapping a skill card opens full-page detail before editor', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('zh'), api: api));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '编辑'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, '详情'), findsNothing);

    await tester.tap(find.text('web-search').first);
    await tester.pumpAndSettle();

    expect(api.detailId, 'general/web-search');
    expect(api.detailScopeId, 'gateway:hermes-work');
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('技能详情'), findsOneWidget);
    final detailEditAction = find.byKey(const ValueKey('skill_app_bar_action'));
    expect(detailEditAction, findsOneWidget);
    final detailEditButton = tester.widget<TextButton>(detailEditAction);
    expect(
      detailEditButton.style?.textStyle?.resolve(<WidgetState>{})?.fontWeight,
      FontWeight.w800,
    );
    expect(find.text('返回技能列表'), findsNothing);
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('技能定义'), findsOneWidget);
    expect(find.text('使用条件'), findsOneWidget);
    expect(find.text('web-search'), findsWidgets);
    expect(find.text('Search the web'), findsWidgets);
    expect(find.text('Use when web lookup is needed'), findsOneWidget);
    expect(find.text('## Existing body\n'), findsOneWidget);
    expect(find.text('查看技能定义、元数据和 SKILL.md 内容。'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, '编辑'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('编辑技能'), findsOneWidget);
    expect(find.text('返回'), findsNothing);
    expect(find.text('基础信息'), findsOneWidget);
    expect(find.text('SKILL.md 正文'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '保存'), findsOneWidget);
  });

  testWidgets('mobile skill detail keeps icon and text edit action', (
    tester,
  ) async {
    final api = _FakeSkillsApiService();
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('zh'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('web-search').first);
    await tester.pumpAndSettle();

    expect(find.text('技能详情'), findsOneWidget);
    final detailEditAction = find.byKey(const ValueKey('skill_app_bar_action'));
    expect(detailEditAction, findsOneWidget);
    final detailEditButton = tester.widget<TextButton>(detailEditAction);
    expect(
      detailEditButton.style?.textStyle?.resolve(<WidgetState>{})?.fontWeight,
      FontWeight.w800,
    );
    expect(find.widgetWithText(TextButton, '编辑'), findsOneWidget);
    expect(
      find.descendant(
        of: detailEditAction,
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsOneWidget,
    );

    await tester.tap(detailEditAction);
    await tester.pumpAndSettle();

    expect(find.text('编辑技能'), findsOneWidget);
  });

  testWidgets('readonly skill detail hides unavailable edit action', (
    tester,
  ) async {
    final api = _ReadonlySkillApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildSubject(locale: const Locale('en'), api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('web-search').first);
    await tester.pumpAndSettle();

    expect(find.text('Skill Detail'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
    expect(api.detailId, 'general/web-search');
  });

  testWidgets('creating after viewing a skill does not reuse selected detail', (
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

    await tester.tap(find.text('web-search').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Skill'));
    await tester.pumpAndSettle();

    expect(find.text('New Skill'), findsOneWidget);
    final nameField = tester.widget<EditableText>(
      find.byType(EditableText).at(0),
    );
    expect(nameField.controller.text, isEmpty);
    expect(find.text('web-search'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Create'), findsOneWidget);
  });

  testWidgets('skill detail opens immediately while body refreshes', (
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

    await tester.tap(find.text('web-search').first);
    await tester.pump();

    expect(api.detailId, 'general/web-search');
    expect(find.text('Skill Detail'), findsOneWidget);
    expect(find.text('Search the web'), findsWidgets);
    expect(find.text('Loading SKILL.md...'), findsOneWidget);

    api.detailCompleter.complete(
      _FakeSkillsApiService.webSearch.copyWith(
        trigger: 'Use when web lookup is needed',
        body: '## Loaded body\n',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loading SKILL.md...'), findsNothing);
    expect(find.text('Use when web lookup is needed'), findsOneWidget);
    expect(find.text('## Loaded body\n'), findsOneWidget);
  });

  testWidgets('editing from list returns to list with one back action', (
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
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Skill Detail'), findsNothing);
    expect(find.text('deploy-helper'), findsOneWidget);
    expect(find.text('New Skill'), findsOneWidget);
  });

  testWidgets('managed skill delete warning shows skill directory', (
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

    await tester.tap(find.widgetWithText(OutlinedButton, '删除').first);
    await tester.pumpAndSettle();

    expect(find.text('删除技能？'), findsOneWidget);
    expect(
      find.text(
        '将删除技能目录 /tmp/skills/general/web-search，此操作不可撤销。\n'
        '是否继续？',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('web-search 的 SKILL.md'), findsNothing);
    expect(find.textContaining('gateway 主机 Clawke skills 目录'), findsNothing);
  });

  testWidgets(
    'desktop shows gateway sidebar without library or all-gateways scopes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildSubject(locale: const Locale('en')));
      await tester.pumpAndSettle();

      expect(find.text('hermes-work'), findsOneWidget);
      expect(find.text('openclaw-lab'), findsOneWidget);
      expect(find.text('Clawke Library'), findsNothing);
      expect(find.text('All Gateways'), findsNothing);

      final newSkillButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'New Skill'),
      );
      expect(newSkillButton.onPressed, isNotNull);
    },
  );

  testWidgets('skills screen derives gateway scopes from cached gateways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('en'),
        api: _GatewayOnlySkillsApiService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('web-search'), findsOneWidget);
    expect(find.text('hermes-work'), findsOneWidget);
    expect(find.text('openclaw-lab'), findsOneWidget);
  });

  testWidgets('skills empty state centers content vertically in its panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(locale: const Locale('zh'), api: _EmptySkillsApiService()),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const ValueKey('empty_state_panel'));
    final content = find.byKey(const ValueKey('empty_state_panel_content'));
    expect(find.text('暂无已安装的 Skills'), findsOneWidget);
    expect(panel, findsOneWidget);
    expect(content, findsOneWidget);
    expect(tester.getRect(panel).bottom, greaterThan(860));
    expect(
      tester.getRect(content).center.dy,
      moreOrLessEquals(tester.getRect(panel).center.dy, epsilon: 1),
    );
  });

  testWidgets(
    'selecting disconnected skills gateway shows generic state without request',
    (tester) async {
      final api = _CountingSkillsApiService();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildSubject(
          locale: const Locale('zh'),
          api: api,
          gateways: const [_hermesGateway, _disconnectedOpenClawGateway],
        ),
      );
      await tester.pumpAndSettle();
      final callsAfterInitialLoad = api.listCalls;

      await tester.tap(find.text('openclaw-lab').first);
      await tester.pumpAndSettle();

      expect(api.listCalls, callsAfterInitialLoad);
      expect(find.text('技能中心'), findsOneWidget);
      expect(find.text('搜索 Skills...'), findsOneWidget);
      expect(find.text('OpenClaw Gateway 未连接'), findsOneWidget);
      expect(find.text('当前不会发起技能请求'), findsOneWidget);
      expect(find.text('暂无已安装的 Skills'), findsNothing);
      expect(find.byIcon(Icons.extension), findsNothing);

      final refreshFinder = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.refresh,
      );
      expect(refreshFinder, findsOneWidget);
      final refreshButton = tester.widget<IconButton>(refreshFinder);
      expect(refreshButton.onPressed, isNull);
      final newSkillButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '新建技能'),
      );
      expect(newSkillButton.onPressed, isNull);
    },
  );

  testWidgets(
    'localized skills display translated fields while editor keeps source fields',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final api = _LocalizedSkillsApiService();

      await tester.pumpWidget(
        buildSubject(locale: const Locale('zh'), api: api),
      );
      await tester.pumpAndSettle();

      expect(find.text('web-search'), findsOneWidget);
      expect(find.text('搜索网页'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '搜索');
      await tester.pumpAndSettle();
      expect(find.text('web-search'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '编辑').first);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller?.text,
        'web-search',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller?.text,
        'Use when web lookup is needed',
      );
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        'Search the web',
      );
      expect(
        tester.widget<TextFormField>(fields.at(4)).controller?.text,
        '## Source body\n',
      );
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

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('en'),
        child: const SkillsManagementScreen(showAppBar: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'hermes-work'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'hermes-work'));
    await tester.pumpAndSettle();

    expect(find.text('openclaw-lab'), findsOneWidget);
    expect(find.text('All Gateways'), findsNothing);

    await tester.tap(find.text('openclaw-lab').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
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
    expect(find.text('openclaw-only'), findsNothing);

    await tester.tap(find.text('openclaw-lab'));
    await tester.pumpAndSettle();

    expect(api.loadedScopes, ['gateway:hermes-work', 'gateway:openclaw-lab']);
    expect(find.text('web-search'), findsNothing);
    expect(find.text('openclaw-only'), findsOneWidget);
  });

  testWidgets('desktop disconnected gateway selection skips skill request', (
    tester,
  ) async {
    final api = _ScopeAwareSkillsApiService();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('en'),
        api: api,
        gateways: const [_hermesGateway, _disconnectedOpenClawGateway],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('web-search'), findsOneWidget);
    expect(find.text('openclaw-only'), findsNothing);

    await tester.tap(find.text('openclaw-lab'));
    await tester.pumpAndSettle();

    expect(api.loadedScopes, ['gateway:hermes-work']);
    expect(find.text('web-search'), findsNothing);
    expect(find.text('openclaw-only'), findsNothing);
    expect(find.text('OpenClaw Gateway disconnected'), findsOneWidget);
    expect(find.text('No skill request will be sent.'), findsOneWidget);
  });

  testWidgets('skills gateway errors do not show bottom snackbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      buildSubject(
        locale: const Locale('zh'),
        api: _UnavailableSkillsApiService(),
        gateways: const [_disconnectedOpenClawGateway],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byKey(const ValueKey('gateway_issue_openclaw-lab')),
      findsOneWidget,
    );
    expect(find.textContaining('Gateway 未连接'), findsOneWidget);
    expect(find.textContaining('网关响应超时'), findsNothing);
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'hermes-work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openclaw-lab'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'openclaw-lab'), findsOneWidget);
    expect(find.text('web-search'), findsNothing);
    expect(find.text('openclaw-only'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(TextButton, 'Create'));
    await tester.pumpAndSettle();

    expect(api.createdDraft?.name, 'qa-helper');
    expect(api.createdDraft?.category, 'testing');
    expect(api.createdDraft?.description, 'Helps validate UI behavior');
    expect(api.createdDraft?.body, contains('Validate Skills UI'));
    expect(api.createdScopeId, 'gateway:hermes-work');
    expect(find.text('qa-helper'), findsWidgets);
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

    expect(find.byType(Dialog), findsNothing);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(3), 'Updated search description');
    await tester.enterText(fields.at(4), '## Updated body\n');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    expect(api.detailId, 'general/web-search');
    expect(api.detailScopeId, 'gateway:hermes-work');
    expect(api.updatedId, 'general/web-search');
    expect(api.updatedScopeId, 'gateway:hermes-work');
    expect(api.updatedDraft?.description, 'Updated search description');
    expect(find.text('Updated search description'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('deploy-helper'), findsOneWidget);
  });

  testWidgets('disabling managed skill toggles without confirmation', (
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

    expect(find.text('Disable managed skill?'), findsNothing);
    expect(api.toggledId, 'general/web-search');
    expect(api.toggledEnabled, isFalse);
    expect(api.toggledScopeId, 'gateway:hermes-work');
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
    await tester.pump();

    expect(find.text('Disable managed skill?'), findsNothing);
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
    await tester.pump();

    expect(find.text('Disable managed skill?'), findsNothing);
    expect(api.toggledId, 'general/web-search');
    final editButtons = tester
        .widgetList<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Edit'))
        .toList();
    expect(editButtons, hasLength(2));
    expect(editButtons[0].onPressed, isNotNull);
    expect(editButtons[1].onPressed, isNotNull);
  });

  testWidgets('opening one skill detail leaves list actions behind', (
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

    await tester.tap(find.text('web-search').first);
    await tester.pump();

    expect(api.detailId, 'general/web-search');
    expect(find.text('Skill Detail'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);
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
