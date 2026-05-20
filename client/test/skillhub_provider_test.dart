import 'dart:async';

import 'package:client/data/repositories/skill_cache_repository.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/models/skillhub_item.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/skillhub_provider.dart';
import 'package:client/services/skillhub_api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _refreshSkillCachesTestProvider = FutureProvider<void>((ref) {
  return refreshSkillCaches(ref);
});

void main() {
  test('loads SkillHub catalog with filters', () async {
    final api = _FakeSkillHubApiService();
    final container = ProviderContainer(
      overrides: [skillHubApiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container
        .read(skillHubControllerProvider.notifier)
        .load(
          query: 'git',
          category: 'coding',
          tag: 'github',
          featured: true,
          gatewayType: 'openclaw',
        );

    final state = container.read(skillHubControllerProvider);
    expect(api.lastQuery, 'git');
    expect(api.lastCategory, 'coding');
    expect(api.lastTag, 'github');
    expect(api.lastFeatured, isTrue);
    expect(api.lastGatewayType, 'openclaw');
    expect(state.items.single.name, 'GitHub Helper');
    expect(state.isLoading, isFalse);
    expect(state.errorMessage, isNull);
  });

  test('loadMore appends the next cursor page with current filters', () async {
    final api = _FakeSkillHubApiService(
      listResults: [
        SkillHubListResult(
          items: [_fakeSkill(id: '204', name: 'GitHub Helper')],
          nextCursor: '1779019593000:5773',
          total: 1,
        ),
        SkillHubListResult(
          items: [_fakeSkill(id: '205', name: 'MegaETH AI Developer')],
          nextCursor: null,
          total: 1,
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [skillHubApiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container
        .read(skillHubControllerProvider.notifier)
        .load(
          query: 'ai',
          category: 'coding',
          tag: 'Coding',
          featured: true,
          gatewayType: 'openclaw',
          limit: 1,
        );

    await container
        .read(skillHubControllerProvider.notifier)
        .loadMore(limit: 1);

    final state = container.read(skillHubControllerProvider);
    expect(api.cursors, [null, '1779019593000:5773']);
    expect(api.limits, [1, 1]);
    expect(api.queries, ['ai', 'ai']);
    expect(api.tags, ['Coding', 'Coding']);
    expect(api.featuredFlags, [true, true]);
    expect(api.gatewayTypes, ['openclaw', 'openclaw']);
    expect(state.items.map((item) => item.name), [
      'GitHub Helper',
      'MegaETH AI Developer',
    ]);
    expect(state.nextCursor, isNull);
    expect(state.isLoadingMore, isFalse);
    expect(state.loadMoreError, isNull);
  });

  test('loads SkillHub detail into selected item', () async {
    final api = _FakeSkillHubApiService();
    final container = ProviderContainer(
      overrides: [skillHubApiServiceProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await container.read(skillHubControllerProvider.notifier).loadDetail('204');

    final state = container.read(skillHubControllerProvider);
    expect(api.lastDetailId, '204');
    expect(state.selected?.originalSkillMd, '# GitHub Helper');
    expect(state.isDetailLoading, isFalse);
  });

  test('installs SkillHub item through local API', () async {
    final api = _FakeSkillHubApiService();
    final cache = _RecordingSkillCacheRepository();
    final container = _skillHubContainer(api, cache);
    addTearDown(container.dispose);

    await container.read(skillHubControllerProvider.notifier).load();
    final item = container.read(skillHubControllerProvider).items.single;

    final installed = await container
        .read(skillHubControllerProvider.notifier)
        .install(item);

    final state = container.read(skillHubControllerProvider);
    expect(installed, isTrue);
    expect(api.lastInstalledId, '204');
    expect(api.lastGatewayId, isNull);
    expect(api.lastGatewayType, isNull);
    expect(api.lastInstallMode, 'auto');
    expect(state.installingIds, isEmpty);
    expect(state.installedIds, {'204'});
    expect(state.installMessages['204'], '安装完成');
    expect(state.errorMessage, isNull);
    await _pumpSkillRefresh();
    expect(cache.syncedGatewayIds, ['openclaw-local']);
    expect(cache.syncedLocales, ['zh']);
  });

  test('refreshSkillCaches syncs every online skills gateway', () async {
    final api = _FakeSkillHubApiService();
    final cache = _RecordingSkillCacheRepository();
    final container = _skillHubContainer(api, cache);
    addTearDown(container.dispose);

    await container.read(_refreshSkillCachesTestProvider.future);

    expect(cache.syncedGatewayIds, ['openclaw-local']);
    expect(cache.syncedLocales, ['zh']);
  });

  test(
    'keeps accepted SkillHub install pending until websocket status',
    () async {
      final api = _FakeSkillHubApiService(
        installResult: const SkillHubInstallResult(
          installId: 'skillhub_1',
          installed: false,
          status: 'accepted',
          message: '安装任务已提交',
        ),
      );
      final cache = _RecordingSkillCacheRepository();
      final container = _skillHubContainer(api, cache);
      addTearDown(container.dispose);

      await container.read(skillHubControllerProvider.notifier).load();
      final item = container.read(skillHubControllerProvider).items.single;

      final submitted = await container
          .read(skillHubControllerProvider.notifier)
          .install(item);

      var state = container.read(skillHubControllerProvider);
      expect(submitted, isTrue);
      expect(state.installingIds, {'204'});
      expect(state.installedIds, isEmpty);
      expect(state.installMessages['204'], '安装任务已提交');
      expect(state.installStatuses['204'], 'accepted');

      container.read(skillHubControllerProvider.notifier).handleInstallStatus({
        'installId': 'skillhub_1',
        'status': 'resolving',
        'message': '正在解析',
      });

      state = container.read(skillHubControllerProvider);
      expect(state.installingIds, {'204'});
      expect(state.installedIds, isEmpty);
      expect(state.installMessages['204'], '正在解析');
      expect(state.installStatuses['204'], 'resolving');

      container.read(skillHubControllerProvider.notifier).handleInstallStatus({
        'installId': 'skillhub_1',
        'status': 'installed',
        'message': '安装完成',
      });

      state = container.read(skillHubControllerProvider);
      expect(state.installingIds, isEmpty);
      expect(state.installedIds, {'204'});
      expect(state.installMessages['204'], '安装完成');
      expect(state.installStatuses['204'], 'installed');
      await _pumpSkillRefresh();
      expect(cache.syncedGatewayIds, ['openclaw-local']);
    },
  );

  test(
    'keeps failed status readable after intermediate websocket status',
    () async {
      final api = _FakeSkillHubApiService(
        installResult: const SkillHubInstallResult(
          installId: 'skillhub_1',
          installed: false,
          status: 'accepted',
          message: '安装任务已提交',
        ),
      );
      final container = ProviderContainer(
        overrides: [skillHubApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(skillHubControllerProvider.notifier).load();
      final item = container.read(skillHubControllerProvider).items.single;
      await container.read(skillHubControllerProvider.notifier).install(item);

      container.read(skillHubControllerProvider.notifier).handleInstallStatus({
        'installId': 'skillhub_1',
        'status': 'downloading',
        'message': '正在下载',
      });
      container.read(skillHubControllerProvider.notifier).handleInstallStatus({
        'installId': 'skillhub_1',
        'status': 'failed',
        'message': '安装包缺少 SKILL.md',
      });

      final state = container.read(skillHubControllerProvider);
      expect(state.installingIds, isEmpty);
      expect(state.installedIds, isEmpty);
      expect(state.installMessages['204'], '安装包缺少 SKILL.md');
      expect(state.installStatuses['204'], 'failed');
      expect(state.errorMessage, '安装包缺少 SKILL.md');
    },
  );

  test(
    'keeps fallback gateway choices when server asks for gateway native retry',
    () async {
      final api = _FakeSkillHubApiService(
        installError: const SkillHubApiException(
          '请选择要安装到的 Gateway',
          actionError: 'fallback_gateway_required',
          details: {
            'gateways': [
              {
                'gatewayId': 'hermes',
                'label': 'Hermes',
                'gatewayType': 'hermes',
              },
            ],
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [skillHubApiServiceProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await container.read(skillHubControllerProvider.notifier).load();
      final item = container.read(skillHubControllerProvider).items.single;

      final submitted = await container
          .read(skillHubControllerProvider.notifier)
          .install(item);

      final state = container.read(skillHubControllerProvider);
      expect(submitted, isFalse);
      expect(state.fallbackGateways.single.gatewayId, 'hermes');
      expect(state.errorMessage, isNull);
    },
  );
}

Future<void> _pumpSkillRefresh() async {
  for (var i = 0; i < 5; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _skillHubContainer(
  _FakeSkillHubApiService api,
  _RecordingSkillCacheRepository cache,
) {
  return ProviderContainer(
    overrides: [
      skillHubApiServiceProvider.overrideWithValue(api),
      skillCacheRepositoryProvider.overrideWithValue(cache),
      onlineGatewayListProvider.overrideWith((ref) {
        return Stream.value(const [
          GatewayInfo(
            gatewayId: 'openclaw-local',
            displayName: 'OpenClaw',
            gatewayType: 'openclaw',
            status: GatewayConnectionStatus.online,
            capabilities: ['chat', 'skills'],
          ),
          GatewayInfo(
            gatewayId: 'chat-only',
            displayName: 'Chat Only',
            gatewayType: 'openclaw',
            status: GatewayConnectionStatus.online,
            capabilities: ['chat'],
          ),
          GatewayInfo(
            gatewayId: 'offline-hermes',
            displayName: 'Hermes',
            gatewayType: 'hermes',
            status: GatewayConnectionStatus.disconnected,
            capabilities: ['chat', 'skills'],
          ),
        ]);
      }),
      localeProvider.overrideWith((ref) {
        return LocaleNotifier(
          initialLocale: const Locale('zh'),
          loadFromPrefs: false,
        );
      }),
    ],
  );
}

class _RecordingSkillCacheRepository implements SkillCacheRepository {
  final List<String> syncedGatewayIds = [];
  final List<String> syncedLocales = [];

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
    syncedGatewayIds.add(scope.gatewayId ?? 'global');
    syncedLocales.add(locale);
    return const [];
  }

  @override
  Future<ManagedSkill?> getCachedSkill(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    return null;
  }

  @override
  Future<ManagedSkill?> getDetail(
    String id,
    SkillScope scope,
    String locale,
  ) async {
    return null;
  }

  @override
  Future<ManagedSkill> create(
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ManagedSkill> update(
    String id,
    SkillDraft draft,
    SkillScope? scope,
    String locale,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id, SkillScope? scope) async {}

  @override
  Future<void> setEnabled(
    String id,
    bool enabled,
    SkillScope? scope,
    String locale,
  ) async {}
}

class _FakeSkillHubApiService extends SkillHubApiService {
  String? lastQuery;
  String? lastCategory;
  String? lastTag;
  bool? lastFeatured;
  String? lastGatewayType;
  String? lastGatewayId;
  String? lastDetailId;
  String? lastInstalledId;
  String? lastInstallMode;
  final SkillHubInstallResult installResult;
  final SkillHubApiException? installError;
  final List<SkillHubListResult>? listResults;
  final List<String?> cursors = [];
  final List<int?> limits = [];
  final List<String?> queries = [];
  final List<String?> tags = [];
  final List<bool?> featuredFlags = [];
  final List<String?> gatewayTypes = [];

  _FakeSkillHubApiService({
    this.installResult = const SkillHubInstallResult(
      installed: true,
      status: 'installed',
      message: '安装完成',
    ),
    this.installError,
    this.listResults,
  });

  @override
  Future<SkillHubListResult> listSkills({
    String? query,
    String? category,
    String? tag,
    bool? featured,
    String? gatewayType,
    int? limit,
    String? cursor,
  }) async {
    lastQuery = query;
    lastCategory = category;
    lastTag = tag;
    lastFeatured = featured;
    lastGatewayType = gatewayType;
    cursors.add(cursor);
    limits.add(limit);
    queries.add(query);
    tags.add(tag);
    featuredFlags.add(featured);
    gatewayTypes.add(gatewayType);
    final results = listResults;
    if (results != null && cursors.length <= results.length) {
      return results[cursors.length - 1];
    }
    return SkillHubListResult(
      items: [_fakeSkill()],
      nextCursor: null,
      total: 1,
    );
  }

  @override
  Future<SkillHubItem> getSkill(String id, {String? gatewayType}) async {
    lastDetailId = id;
    return const SkillHubItem(
      id: '204',
      slug: 'github-helper',
      name: 'GitHub Helper',
      summary: 'GitHub workflow helper',
      category: 'coding',
      tags: ['github'],
      source: 'clawhub',
      sourceOwner: 'garrytan',
      sourceUrl: 'https://clawhub.ai/garrytan/gstack',
      featured: true,
      downloadCount: 1200,
      version: '1.2.1',
      changelog: 'Initial release',
      license: 'MIT-0',
      packageUrl: 'https://local.clawke.ai/upload/package.zip',
      packageSha256: 'sha256:abc',
      packageSize: 45678,
      compatibleGateways: ['openclaw'],
      compatibility: 'compatible',
      packageType: 'bundle',
      packageSkillMdPaths: ['SKILL.md'],
      updatedAt: 1778664000000,
      status: 'published',
      usage: 'Use GitHub Helper',
      originalSkillMd: '# GitHub Helper',
    );
  }

  @override
  Future<SkillHubInstallResult> installSkill(
    SkillHubItem item, {
    String? gatewayId,
    String? gatewayType,
    String? installMode,
  }) async {
    if (installError != null) throw installError!;
    lastInstalledId = item.id;
    lastGatewayId = gatewayId;
    lastGatewayType = gatewayType;
    lastInstallMode = installMode;
    return installResult;
  }
}

SkillHubItem _fakeSkill({
  String id = '204',
  String name = 'GitHub Helper',
  String slug = 'github-helper',
}) {
  return SkillHubItem(
    id: id,
    slug: slug,
    name: name,
    summary: 'GitHub workflow helper',
    category: 'coding',
    tags: ['github'],
    source: 'clawhub',
    sourceOwner: 'garrytan',
    sourceUrl: '',
    featured: true,
    downloadCount: 1200,
    version: '1.2.1',
    changelog: '',
    license: '',
    packageUrl: '',
    packageSha256: 'sha256:abc',
    packageSize: 45678,
    compatibleGateways: ['openclaw'],
    compatibility: 'compatible',
    packageType: 'bundle',
    packageSkillMdPaths: [],
    updatedAt: 1778664000000,
    status: 'published',
    usage: '',
    originalSkillMd: '',
  );
}
