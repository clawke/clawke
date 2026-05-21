import 'dart:async';

import 'package:client/l10n/app_localizations.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/models/skillhub_item.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/skillhub_provider.dart';
import 'package:client/services/skillhub_api_service.dart';
import 'package:client/widgets/app_notice_bar.dart';
import 'package:client/widgets/copyable_text.dart';
import 'package:client/widgets/empty_state_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _SkillHubPage { catalog, detail }

const _skillHubCatalogPageSize = 30;

const _categoryOptions = <_CategoryOption>[
  _CategoryOption(
    kind: _CategoryOptionKind.all,
    category: null,
    featured: null,
  ),
  _CategoryOption(
    kind: _CategoryOptionKind.featured,
    category: null,
    featured: true,
  ),
  _CategoryOption(
    kind: _CategoryOptionKind.coding,
    category: 'coding',
    featured: null,
  ),
];

final _skillHubBuiltInInstallsProvider =
    FutureProvider.family<List<_GatewaySkillInstall>, String>((
      ref,
      slug,
    ) async {
      final normalizedSlug = _normalizeSkillKey(slug);
      if (normalizedSlug.isEmpty) return const [];
      final gateways = await ref.watch(onlineGatewayListProvider.future);
      final api = ref.watch(skillsApiServiceProvider);
      final candidates = _installableGateways(gateways);
      final results = await Future.wait(
        candidates.map((gateway) async {
          final scope = SkillScope(
            id: gateway.gatewayId,
            type: 'gateway',
            label: gateway.displayName,
            description: '${gateway.gatewayType} gateway',
            readonly: false,
            gatewayId: gateway.gatewayId,
          );
          try {
            final skills = await api.listSkills(scope: scope);
            final skill = skills
                .where(
                  (skill) => _managedSkillMatchesSlug(skill, normalizedSlug),
                )
                .firstOrNull;
            return skill == null
                ? null
                : _GatewaySkillInstall(gateway: gateway, skill: skill);
          } catch (_) {
            return null;
          }
        }),
      );
      return results.whereType<_GatewaySkillInstall>().toList();
    });

final _skillHubBuiltInSlugsProvider = StreamProvider<Set<String>>((ref) {
  final gateways =
      ref.watch(onlineGatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
  final candidates = _installableGateways(gateways);
  if (candidates.isEmpty) return Stream.value(const <String>{});

  final cache = ref.watch(skillCacheRepositoryProvider);
  final locale = ref.watch(
    localeProvider.select((locale) => locale?.languageCode ?? 'en'),
  );
  final controller = StreamController<Set<String>>();
  final latest = <String, List<ManagedSkill>>{};
  var closed = false;

  void emit() {
    if (closed || controller.isClosed) return;
    controller.add(_installedSlugsFromSkills(latest.values.expand((e) => e)));
  }

  final subscriptions = <StreamSubscription<List<ManagedSkill>>>[];
  for (final gateway in candidates) {
    final gatewayId = gateway.gatewayId;
    subscriptions.add(
      cache
          .watchSkills(gatewayId, locale)
          .listen(
            (skills) {
              latest[gatewayId] = skills;
              emit();
            },
            onError: (_) {
              latest[gatewayId] = const [];
              emit();
            },
          ),
    );
    unawaited(
      cache
          .syncGateway(_skillScopeForGateway(gateway), locale)
          .catchError((Object _) => const <ManagedSkill>[]),
    );
  }

  ref.onDispose(() {
    closed = true;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(controller.close());
  });

  return controller.stream;
});

class SkillHubScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const SkillHubScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<SkillHubScreen> createState() => _SkillHubScreenState();
}

class _SkillHubScreenState extends ConsumerState<SkillHubScreen> {
  final _searchController = TextEditingController();
  final _catalogScrollController = ScrollController();
  _SkillHubPage _page = _SkillHubPage.catalog;
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _catalogScrollController.addListener(_handleCatalogScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalog());
  }

  @override
  void dispose() {
    _catalogScrollController.removeListener(_handleCatalogScroll);
    _catalogScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SkillHubState>(
      skillHubControllerProvider,
      _handleInstallStatusChange,
    );
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(skillHubControllerProvider);
    final content = Container(
      color: colorScheme.surface,
      child: _page == _SkillHubPage.catalog
          ? _buildCatalog(state)
          : _buildDetail(state),
    );

    if (!widget.showAppBar) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SkillHub'),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: _page == _SkillHubPage.detail
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: context.l10n.skillHubBack,
                onPressed: _showCatalog,
              )
            : null,
      ),
      body: content,
    );
  }

  Widget _buildCatalog(SkillHubState state) {
    final builtInSlugs =
        ref.watch(_skillHubBuiltInSlugsProvider).valueOrNull ??
        const <String>{};
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final padding = compact ? 16.0 : 28.0;
        final contentWidth = constraints.maxWidth - padding * 2;
        const gap = 14.0;
        const minCardWidth = 280.0;
        final availableColumns = ((contentWidth + gap) / (minCardWidth + gap))
            .floor();
        final columnCount = compact ? 1 : availableColumns.clamp(1, 3).toInt();
        final cardExtent = compact ? 190.0 : 168.0;

        return RefreshIndicator(
          onRefresh: () => _loadCatalog(force: true),
          child: CustomScrollView(
            controller: _catalogScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _SkillHubHeader(isLoading: state.isLoading),
                    const SizedBox(height: 18),
                    _buildSearchRow(compact),
                    const SizedBox(height: 14),
                    _buildTagTabs(),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      AppNoticeBar.error(
                        message: _localizedSkillHubMessage(state.errorMessage!),
                        onDismiss: () => ref
                            .read(skillHubControllerProvider.notifier)
                            .clearError(),
                      ),
                    ],
                    const SizedBox(height: 18),
                  ]),
                ),
              ),
              if (state.isLoading && state.items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.items.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                  sliver: SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStatePanel(
                      icon: Icons.extension_off_outlined,
                      title: context.l10n.skillHubEmptyTitle,
                      message: context.l10n.skillHubEmptyMessage,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
                  sliver: columnCount > 1
                      ? SliverGrid.builder(
                          itemCount: state.items.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columnCount,
                                mainAxisSpacing: gap,
                                crossAxisSpacing: gap,
                                mainAxisExtent: cardExtent,
                              ),
                          itemBuilder: (context, index) => _SkillHubCard(
                            item: state.items[index],
                            installFlags: _catalogInstallFlags(
                              state.items[index],
                              state,
                              builtInSlugs,
                            ),
                            onTap: _openDetail,
                          ),
                        )
                      : SliverList.builder(
                          itemCount: state.items.length,
                          itemBuilder: (context, index) => Padding(
                            padding: EdgeInsets.only(
                              bottom: index == state.items.length - 1 ? 0 : gap,
                            ),
                            child: SizedBox(
                              height: cardExtent,
                              child: _SkillHubCard(
                                item: state.items[index],
                                installFlags: _catalogInstallFlags(
                                  state.items[index],
                                  state,
                                  builtInSlugs,
                                ),
                                onTap: _openDetail,
                              ),
                            ),
                          ),
                        ),
                ),
              _buildCatalogFooter(state, padding),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCatalogFooter(SkillHubState state, double padding) {
    if (state.items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    Widget child = const SizedBox(height: 24);
    if (state.isLoadingMore) {
      child = const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (state.loadMoreError != null) {
      child = Center(
        child: OutlinedButton.icon(
          onPressed: _loadMoreCatalog,
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.skillHubLoadRetry),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padding, 14, padding, padding),
      sliver: SliverToBoxAdapter(child: child),
    );
  }

  Widget _buildSearchRow(bool compact) {
    final searchField = TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => unawaited(_loadCatalog()),
      decoration: InputDecoration(
        hintText: context.l10n.skillHubSearchHint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
      ),
    );

    final searchButton = FilledButton.icon(
      onPressed: () => unawaited(_loadCatalog()),
      icon: const Icon(Icons.search),
      label: Text(context.l10n.skillHubSearch),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [searchField, const SizedBox(height: 10), searchButton],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 10),
        searchButton,
      ],
    );
  }

  Widget _buildTagTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _categoryOptions.length; i++) ...[
            Padding(
              padding: EdgeInsets.only(
                right: i == _categoryOptions.length - 1 ? 0 : 8,
              ),
              child: FilterChip(
                label: Text(_categoryOptionLabel(context, _categoryOptions[i])),
                selected: _selectedCategoryIndex == i,
                onSelected: (_) {
                  setState(() => _selectedCategoryIndex = i);
                  unawaited(_loadCatalog());
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail(SkillHubState state) {
    final item = state.selected;
    if (state.isDetailLoading && item == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (item == null) {
      return EmptyStatePanel(
        icon: Icons.extension_off_outlined,
        title: context.l10n.skillHubNotFoundTitle,
        message: context.l10n.skillHubNotFoundMessage,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final padding = compact ? 16.0 : 28.0;
        final detail = _DetailMain(
          item: item,
          showCompatibility: false,
          includeLongSections: !compact,
        );
        final longSections = _DetailLongSections(item: item);
        final builtInInstalls = ref.watch(
          _skillHubBuiltInInstallsProvider(item.slug),
        );
        final gatewayInstalls = builtInInstalls.valueOrNull ?? const [];
        final isSkillHubInstalled = _isSkillHubItemInstalled(item, state);
        final installStatus = state.installStatuses[item.id];
        final installMessage = state.installMessages[item.id];
        final side = _DetailSidePanel(
          item: item,
          onInstall: _install,
          isInstalling: state.installingIds.contains(item.id),
          isSkillHubInstalled: isSkillHubInstalled,
          isCheckingInstallStatus:
              builtInInstalls.isLoading && !builtInInstalls.hasValue,
          builtInInstalls: gatewayInstalls,
          skillHubInstallPath:
              state.skillHubInstallPaths[_normalizeSkillKey(item.slug)],
          installStatus: installStatus,
          installMessage: installMessage,
          canInstallToAnotherGateway: false,
        );

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.all(padding),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (!widget.showAppBar) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _showCatalog,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(context.l10n.skillHubBackToHub),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (compact) ...[
                    detail,
                    const SizedBox(height: 14),
                    side,
                    const SizedBox(height: 14),
                    longSections,
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: detail),
                        const SizedBox(width: 16),
                        Expanded(flex: 3, child: side),
                      ],
                    ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadCatalog({bool force = false}) async {
    final option = _categoryOptions[_selectedCategoryIndex];
    await ref
        .read(skillHubControllerProvider.notifier)
        .load(
          query: _searchController.text.trim(),
          category: option.category,
          featured: option.featured,
          limit: _skillHubCatalogPageSize,
        );
    if (!mounted || _page != _SkillHubPage.catalog) return;
    if (_catalogScrollController.hasClients) {
      _catalogScrollController.jumpTo(0);
    }
  }

  void _handleCatalogScroll() {
    if (_page != _SkillHubPage.catalog ||
        !_catalogScrollController.hasClients) {
      return;
    }
    if (_catalogScrollController.position.extentAfter > 600) return;
    _loadMoreCatalog();
  }

  void _loadMoreCatalog() {
    unawaited(
      ref
          .read(skillHubControllerProvider.notifier)
          .loadMore(limit: _skillHubCatalogPageSize),
    );
  }

  void _openDetail(SkillHubItem item) {
    setState(() => _page = _SkillHubPage.detail);
    unawaited(
      ref.read(skillHubControllerProvider.notifier).loadDetail(item.id),
    );
  }

  void _showCatalog() {
    setState(() => _page = _SkillHubPage.catalog);
  }

  Future<void> _install(SkillHubItem item) async {
    var submitted = await ref
        .read(skillHubControllerProvider.notifier)
        .install(item);
    if (!mounted) return;

    var state = ref.read(skillHubControllerProvider);
    if (!submitted && state.fallbackGateways.isNotEmpty) {
      final gateway = await _selectFallbackGateway(state.fallbackGateways);
      if (!mounted || gateway == null) return;
      submitted = await ref
          .read(skillHubControllerProvider.notifier)
          .install(
            item,
            gatewayId: gateway.gatewayId,
            gatewayType: gateway.gatewayType,
            installMode: 'gateway_native',
          );
    }

    if (!mounted) return;
    state = ref.read(skillHubControllerProvider);
    final status = state.installStatuses[item.id];
    final errorMessage = state.errorMessage;
    final message = submitted
        ? _messageForInstallStatus(status)
        : errorMessage == null
        ? context.l10n.skillHubInstallFailed
        : _localizedSkillHubMessage(errorMessage);
    _showSnack(message);
    if (_isSkillHubItemInstalled(item, state)) {
      ref.invalidate(_skillHubBuiltInInstallsProvider(item.slug));
    }
  }

  String _localizedSkillHubMessage(String message) {
    return switch (message) {
      skillHubReceiveTimeoutUiCode => context.l10n.skillHubRequestTimeout,
      skillHubNetworkErrorUiCode => context.l10n.skillHubNetworkError,
      _ => message,
    };
  }

  Future<SkillHubFallbackGateway?> _selectFallbackGateway(
    List<SkillHubFallbackGateway> candidates,
  ) async {
    if (candidates.isEmpty) return null;
    return showDialog<SkillHubFallbackGateway>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.skillHubSelectGateway),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final gateway in candidates)
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(gateway.label),
                  subtitle: Text(
                    '${gateway.gatewayType} · ${gateway.gatewayId}',
                  ),
                  onTap: () => Navigator.of(context).pop(gateway),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        content: CopyableText(message),
      ),
    );
  }

  void _handleInstallStatusChange(SkillHubState? previous, SkillHubState next) {
    if (previous == null) return;
    for (final entry in next.installStatuses.entries) {
      final itemId = entry.key;
      final status = entry.value;
      final previousStatus = previous.installStatuses[itemId];
      if (previousStatus == status) continue;

      if (status == 'installed' || status == 'failed') {
        final message = status == 'failed'
            ? next.installMessages[itemId] ?? _messageForInstallStatus(status)
            : _messageForInstallStatus(status);
        _showSnack(message);
      }

      if (status == 'installed') {
        final item = _itemById(next, itemId);
        if (item != null) {
          ref.invalidate(_skillHubBuiltInInstallsProvider(item.slug));
        }
      }
    }
  }

  SkillHubItem? _itemById(SkillHubState state, String itemId) {
    final selected = state.selected;
    if (selected != null && selected.id == itemId) return selected;
    for (final item in state.items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  _CatalogInstallFlags _catalogInstallFlags(
    SkillHubItem item,
    SkillHubState state,
    Set<String> builtInSlugs,
  ) {
    final normalizedSlug = _normalizeSkillKey(item.slug);
    return _CatalogInstallFlags(
      skillHubInstalled: _isSkillHubItemInstalled(item, state),
      builtInInstalled: builtInSlugs.contains(normalizedSlug),
    );
  }

  String _messageForInstallStatus(String? status) {
    return _installStatusLabel(context.l10n, status);
  }
}

class _SkillHubHeader extends StatelessWidget {
  final bool isLoading;

  const _SkillHubHeader({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SkillHub',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.skillHubSubtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isLoading) ...[
          const SizedBox(width: 12),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}

class _SkillHubCard extends StatelessWidget {
  final SkillHubItem item;
  final _CatalogInstallFlags installFlags;
  final ValueChanged<SkillHubItem> onTap;

  const _SkillHubCard({
    required this.item,
    required this.installFlags,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final markerPills = [
      if (installFlags.skillHubInstalled)
        _MetaPill(label: l10n.skillHubInstalled, color: colorScheme.primary),
      if (installFlags.builtInInstalled)
        _MetaPill(
          label: l10n.skillHubBuiltInInstalled,
          color: colorScheme.tertiary,
        ),
      if (!installFlags.skillHubInstalled &&
          !installFlags.builtInInstalled &&
          item.featured)
        _MetaPill(label: l10n.skillHubFeatured, color: colorScheme.primary),
    ];
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => onTap(item),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkillAvatar(item: item),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.slug,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _DownloadStat(count: item.downloadCount),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        item.summary.isEmpty
                            ? l10n.skillHubNoSummary
                            : item.summary,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(height: 1.35),
                      ),
                    ),
                  ),
                ],
              ),
              if (markerPills.isNotEmpty)
                Positioned(
                  top: 28,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < markerPills.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        markerPills[i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailMain extends StatelessWidget {
  final SkillHubItem item;
  final bool showCompatibility;
  final bool includeLongSections;

  const _DetailMain({
    required this.item,
    required this.showCompatibility,
    this.includeLongSections = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkillAvatar(item: item, large: true),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in item.tags.take(4))
                              _MetaPill(label: tag),
                            if (item.featured)
                              _MetaPill(
                                label: l10n.skillHubFeatured,
                                color: colorScheme.primary,
                              ),
                            if (showCompatibility)
                              _CompatibilityPill(value: item.compatibility),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.name,
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CopyableText(
                item.summary.isEmpty ? l10n.skillHubNoSummary : item.summary,
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
        if (includeLongSections) ...[
          const SizedBox(height: 14),
          _DetailLongSections(item: item),
        ],
      ],
    );
  }
}

class _DetailLongSections extends StatelessWidget {
  final SkillHubItem item;

  const _DetailLongSections({required this.item});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: l10n.skillHubUsageTitle,
          child: Text(
            item.usage.isEmpty ? l10n.skillHubUsageUnavailable : item.usage,
            style: textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: 'SKILL.md',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              item.originalSkillMd.isEmpty
                  ? l10n.skillHubSkillMdUnavailable
                  : item.originalSkillMd,
              style: textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailSidePanel extends StatelessWidget {
  final SkillHubItem item;
  final ValueChanged<SkillHubItem> onInstall;
  final bool isInstalling;
  final bool isSkillHubInstalled;
  final bool isCheckingInstallStatus;
  final List<_GatewaySkillInstall> builtInInstalls;
  final String? skillHubInstallPath;
  final String? installStatus;
  final String? installMessage;
  final bool canInstallToAnotherGateway;

  const _DetailSidePanel({
    required this.item,
    required this.onInstall,
    required this.isInstalling,
    required this.isSkillHubInstalled,
    required this.isCheckingInstallStatus,
    required this.builtInInstalls,
    required this.skillHubInstallPath,
    required this.installStatus,
    required this.installMessage,
    required this.canInstallToAnotherGateway,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final incompatible = item.compatibility == 'incompatible';
    final localStatus = _localStatusLabel(
      l10n: l10n,
      incompatible: incompatible,
      isCheckingInstallStatus: isCheckingInstallStatus,
      isSkillHubInstalled: isSkillHubInstalled,
      isInstalling: isInstalling,
      installStatus: installStatus,
      installMessage: installMessage,
    );
    final normalizedSkillHubPath = skillHubInstallPath?.trim();
    final hasSkillHubPath =
        normalizedSkillHubPath != null && normalizedSkillHubPath.isNotEmpty;
    final hasSkillHubActivity =
        isInstalling ||
        isCheckingInstallStatus ||
        installStatus == 'failed' ||
        (installStatus != null &&
            installStatus != 'installed' &&
            installStatus != 'not_installed');
    final showSkillHubStatus = isSkillHubInstalled || hasSkillHubActivity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: l10n.skillHubInstallStatusTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showSkillHubStatus)
                _StatusRow(
                  label: 'SkillHub',
                  value: localStatus,
                  tooltip: isSkillHubInstalled && hasSkillHubPath
                      ? normalizedSkillHubPath
                      : null,
                ),
              if (builtInInstalls.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final install in builtInInstalls) ...[
                  _StatusRow(
                    label: install.gatewayLabel,
                    value: l10n.skillHubBuiltInInstalled,
                    tooltip: install.displayPath.isEmpty
                        ? null
                        : install.displayPath,
                  ),
                  const SizedBox(height: 6),
                ],
              ],
              _StatusRow(
                label: l10n.skillHubVersion,
                value: item.version.isEmpty ? '-' : item.version,
              ),
              _StatusRow(
                label: l10n.skillHubDownloads,
                value: _formatCount(item.downloadCount),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    incompatible ||
                        isInstalling ||
                        (isSkillHubInstalled && !canInstallToAnotherGateway)
                    ? null
                    : () => onInstall(item),
                icon: isInstalling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(
                  incompatible
                      ? l10n.skillHubInstallDisabled
                      : isInstalling
                      ? l10n.skillHubInstalling
                      : isSkillHubInstalled
                      ? canInstallToAnotherGateway
                            ? l10n.skillHubInstallToAnotherGateway
                            : l10n.skillHubInstalled
                      : l10n.skillHubInstall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: l10n.skillHubPackageInfo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusRow(
                label: l10n.skillHubPackageType,
                value: item.packageType.isEmpty ? '-' : item.packageType,
              ),
              _StatusRow(
                label: l10n.skillHubPackageSize,
                value: _formatBytes(item.packageSize),
              ),
              _StatusRow(
                label: l10n.skillHubSource,
                value: item.sourceOwner.isEmpty
                    ? item.source
                    : item.sourceOwner,
              ),
              if (item.packageSkillMdPaths.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final path in item.packageSkillMdPaths)
                      _MetaPill(label: path),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Panel(
          title: l10n.skillHubCompatibleGateways,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: item.compatibleGateways.isEmpty
                ? [
                    _MetaPill(
                      label: l10n.skillHubUnknown,
                      color: colorScheme.outline,
                    ),
                  ]
                : [
                    for (final gateway in item.compatibleGateways)
                      _MetaPill(label: gateway),
                  ],
          ),
        ),
        if (item.changelog.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Panel(
            title: l10n.skillHubChangelog,
            child: Text(item.changelog, style: textTheme.bodyMedium),
          ),
        ],
      ],
    );
  }

  String _localStatusLabel({
    required AppLocalizations l10n,
    required bool incompatible,
    required bool isCheckingInstallStatus,
    required bool isSkillHubInstalled,
    required bool isInstalling,
    required String? installStatus,
    required String? installMessage,
  }) {
    if (incompatible) return l10n.skillHubIncompatible;
    if (isInstalling) {
      final known = _knownInstallStatusLabel(l10n, installStatus);
      if (known != null) return known;
      final message = installMessage?.trim();
      if (message != null && message.isNotEmpty) return message;
      return l10n.skillHubInstallStatusDefault;
    }
    if (installStatus == 'failed') {
      final message = installMessage?.trim();
      if (message != null && message.isNotEmpty) return message;
      return l10n.skillHubInstallFailed;
    }
    if (isCheckingInstallStatus) return l10n.skillHubChecking;
    if (isSkillHubInstalled) return l10n.skillHubInstalled;
    return l10n.skillHubNotInstalled;
  }
}

class _Panel extends StatelessWidget {
  final String? title;
  final Widget child;

  const _Panel({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

class _SkillAvatar extends StatelessWidget {
  final SkillHubItem item;
  final bool large;

  const _SkillAvatar({required this.item, this.large = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = large ? 72.0 : 48.0;
    final initial = item.name.trim().isEmpty
        ? '#'
        : item.name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final Color? color;

  const _MetaPill({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final base = color ?? colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withValues(alpha: 0.36)),
      ),
      child: CopyableText(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DownloadStat extends StatelessWidget {
  final int count;

  const _DownloadStat({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.download_outlined,
          size: 15,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          _formatCount(count),
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _CompatibilityPill extends StatelessWidget {
  final String value;

  const _CompatibilityPill({required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (label, color) = switch (value) {
      'compatible' => (l10n.skillHubCompatible, colorScheme.primary),
      'incompatible' => (l10n.skillHubIncompatible, colorScheme.error),
      _ => (l10n.skillHubNoGatewaySelected, colorScheme.outline),
    };
    return _MetaPill(label: label, color: color);
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final String? tooltip;

  const _StatusRow({required this.label, required this.value, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltipMessage = tooltip?.trim();
    final hasTooltip = tooltipMessage != null && tooltipMessage.isNotEmpty;
    final rowTextStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(height: 1.0);
    final valueText = CopyableText(
      value,
      textAlign: TextAlign.right,
      maxLines: 2,
      style: rowTextStyle?.copyWith(
        color: hasTooltip ? colorScheme.primary : null,
        fontWeight: FontWeight.w700,
        decoration: hasTooltip ? TextDecoration.underline : null,
        decorationColor: hasTooltip ? colorScheme.primary : null,
        decorationStyle: TextDecorationStyle.dotted,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: CopyableText(
              label,
              style: rowTextStyle?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: !hasTooltip
                ? valueText
                : Tooltip(
                    message: tooltipMessage,
                    triggerMode: TooltipTriggerMode.tap,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.help,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: valueText),
                          const SizedBox(width: 3),
                          Baseline(
                            baseline: 13,
                            baselineType: TextBaseline.alphabetic,
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CatalogInstallFlags {
  final bool skillHubInstalled;
  final bool builtInInstalled;

  const _CatalogInstallFlags({
    required this.skillHubInstalled,
    required this.builtInInstalled,
  });
}

class _GatewaySkillInstall {
  final GatewayInfo gateway;
  final ManagedSkill skill;

  const _GatewaySkillInstall({required this.gateway, required this.skill});

  String get gatewayLabel => gateway.displayName;

  String get displayPath => skill.displayPath;
}

enum _CategoryOptionKind { all, featured, coding }

class _CategoryOption {
  final _CategoryOptionKind kind;
  final String? category;
  final bool? featured;

  const _CategoryOption({
    required this.kind,
    required this.category,
    required this.featured,
  });
}

String _categoryOptionLabel(BuildContext context, _CategoryOption option) {
  final l10n = context.l10n;
  return switch (option.kind) {
    _CategoryOptionKind.all => l10n.skillHubTagAll,
    _CategoryOptionKind.featured => l10n.skillHubTagFeatured,
    _CategoryOptionKind.coding => 'Coding',
  };
}

String _installStatusLabel(AppLocalizations l10n, String? status) {
  return _knownInstallStatusLabel(l10n, status) ??
      l10n.skillHubInstallStatusDefault;
}

String? _knownInstallStatusLabel(AppLocalizations l10n, String? status) {
  return switch (status) {
    'accepted' => l10n.skillHubInstallStatusAccepted,
    'resolving' => l10n.skillHubInstallStatusResolving,
    'downloading' => l10n.skillHubInstallStatusDownloading,
    'verifying' => l10n.skillHubInstallStatusVerifying,
    'extracting' => l10n.skillHubInstallStatusExtracting,
    'installing' => l10n.skillHubInstallStatusInstallingSkill,
    'recording' => l10n.skillHubInstallStatusRecording,
    'refreshing' => l10n.skillHubInstallStatusRefreshingCache,
    'fallback_pending' => l10n.skillHubInstallStatusFallbackPending,
    'gateway_installing' => l10n.skillHubInstallStatusGatewayInstalling,
    'installed' => l10n.skillHubInstallStatusInstalled,
    'failed' => l10n.skillHubInstallStatusFailed,
    _ => null,
  };
}

List<GatewayInfo> _installableGateways(List<GatewayInfo> gateways) {
  return gateways.where((gateway) {
    if (gateway.status != GatewayConnectionStatus.online) return false;
    if (!gateway.supports('skills')) return false;
    return true;
  }).toList();
}

SkillScope _skillScopeForGateway(GatewayInfo gateway) {
  return SkillScope(
    id: 'gateway:${gateway.gatewayId}',
    type: 'gateway',
    label: gateway.displayName,
    description: gateway.gatewayId,
    readonly: false,
    gatewayId: gateway.gatewayId,
  );
}

Set<String> _installedSlugsFromSkills(Iterable<ManagedSkill> skills) {
  final slugs = <String>{};
  for (final skill in skills) {
    final idSlug = _normalizeSkillKey(_skillKeyFromManagedId(skill.id));
    if (idSlug.isNotEmpty) slugs.add(idSlug);
    final nameSlug = _normalizeSkillKey(skill.name);
    if (nameSlug.isNotEmpty) slugs.add(nameSlug);
  }
  return slugs;
}

bool _managedSkillMatchesSlug(ManagedSkill skill, String normalizedSlug) {
  return _normalizeSkillKey(_skillKeyFromManagedId(skill.id)) ==
          normalizedSlug ||
      _normalizeSkillKey(skill.name) == normalizedSlug;
}

bool _isSkillHubItemInstalled(SkillHubItem item, SkillHubState state) {
  return state.installedIds.contains(item.id) ||
      state.skillHubInstalledSlugs.contains(_normalizeSkillKey(item.slug));
}

String _skillKeyFromManagedId(String id) {
  final parts = id.split('/');
  return parts.isEmpty ? id : parts.last;
}

String _normalizeSkillKey(String value) {
  return value.trim().toLowerCase();
}

String _formatCount(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final left = raw.length - i;
    buffer.write(raw[i]);
    if (left > 1 && left % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

String _formatBytes(int value) {
  if (value <= 0) return '-';
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
}
