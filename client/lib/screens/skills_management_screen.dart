import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/l10n/app_localizations.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/skills_provider.dart';
import 'package:client/widgets/app_snack_bar.dart';
import 'package:client/widgets/empty_state_panel.dart';
import 'package:client/widgets/gateway_selector_pane.dart';
import 'package:client/widgets/gateway_unavailable_panel.dart';

enum _SkillStatusFilter { all, enabled, disabled }

enum _SkillSourceFilter { all, managed, external, readonly }

enum _SkillPage { list, detail, edit }

class SkillsManagementScreen extends ConsumerStatefulWidget {
  final bool showAppBar;

  const SkillsManagementScreen({super.key, this.showAppBar = false});

  @override
  ConsumerState<SkillsManagementScreen> createState() =>
      _SkillsManagementScreenState();
}

class _SkillsManagementScreenState
    extends ConsumerState<SkillsManagementScreen> {
  final _searchController = TextEditingController();
  _SkillStatusFilter _statusFilter = _SkillStatusFilter.all;
  _SkillSourceFilter _sourceFilter = _SkillSourceFilter.all;
  _SkillPage _page = _SkillPage.list;
  String? _activeSkillId;
  bool _returnToDetailAfterEdit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshGatewayCache();
      _syncGateways();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<GatewayInfo>>>(gatewayListProvider, (_, next) {
      final gateways = next.valueOrNull;
      if (gateways != null) _syncGateways(gateways);
    });

    final state = ref.watch(skillsControllerProvider);
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
                selectedGatewayId: state.selectedScope?.gatewayId,
                capability: 'skills',
                errorGatewayId:
                    state.errorGatewayId ?? unavailableGateway?.gatewayId,
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

    if (!widget.showAppBar || _page != _SkillPage.list) return content;

    return Scaffold(appBar: _buildAppBar(state, gateways), body: content);
  }

  PreferredSizeWidget _buildAppBar(
    SkillsState state,
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
      title: Text(context.l10n.navSkills),
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: context.l10n.skillsRefresh,
          onPressed: state.isLoading || hasGatewayIssue
              ? null
              : () => unawaited(_refreshSkills(gateways)),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: context.l10n.skillsNewSkill,
          onPressed:
              state.isScopeReadOnly ||
                  state.selectedScope == null ||
                  hasGatewayIssue
              ? null
              : () => _openEditor(),
        ),
      ],
    );
  }

  List<ManagedSkill> _filtered(List<ManagedSkill> skills) {
    final query = _searchController.text.trim().toLowerCase();
    return skills.where((skill) {
      final matchesStatus = switch (_statusFilter) {
        _SkillStatusFilter.all => true,
        _SkillStatusFilter.enabled => skill.enabled,
        _SkillStatusFilter.disabled => !skill.enabled,
      };
      if (!matchesStatus) return false;
      final matchesSource = switch (_sourceFilter) {
        _SkillSourceFilter.all => true,
        _SkillSourceFilter.managed => skill.source == 'managed',
        _SkillSourceFilter.external => skill.source == 'external',
        _SkillSourceFilter.readonly => skill.source == 'readonly',
      };
      if (!matchesSource) return false;
      if (query.isEmpty) return true;
      return skill.displayName.toLowerCase().contains(query) ||
          skill.displayDescription.toLowerCase().contains(query) ||
          skill.name.toLowerCase().contains(query) ||
          skill.description.toLowerCase().contains(query) ||
          skill.category.toLowerCase().contains(query);
    }).toList();
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

  void _syncGateways([List<GatewayInfo>? gateways]) {
    final source =
        gateways ??
        ref.read(gatewayListProvider).valueOrNull ??
        const <GatewayInfo>[];
    final state = ref.read(skillsControllerProvider);
    final ordered = orderGatewaysForSelection(
      source,
      'skills',
      currentGatewayId: state.selectedScope?.gatewayId,
    );
    final selected = gatewayForSelection(
      source,
      'skills',
      currentGatewayId: state.selectedScope?.gatewayId,
    );
    if (selected != null && gatewayUnavailableFor(selected, 'skills')) {
      _markSkillsGatewayUnavailable(ordered, selected);
      return;
    }
    unawaited(
      ref.read(skillsControllerProvider.notifier).syncGateways(ordered),
    );
  }

  Future<void> _refreshSkills(List<GatewayInfo> gateways) {
    final state = ref.read(skillsControllerProvider);
    final selected = gatewayById(gateways, state.selectedScope?.gatewayId);
    if (selected != null && gatewayUnavailableFor(selected, 'skills')) {
      final ordered = orderGatewaysForSelection(
        gateways,
        'skills',
        currentGatewayId: selected.gatewayId,
      );
      _markSkillsGatewayUnavailable(ordered, selected);
      return Future.value();
    }
    return ref
        .read(skillsControllerProvider.notifier)
        .syncGateways(
          orderGatewaysForSelection(
            gateways,
            'skills',
            currentGatewayId: state.selectedScope?.gatewayId,
          ),
          force: true,
        );
  }

  ManagedSkill? _activeSkill(SkillsState state) {
    final id = _activeSkillId;
    if (id == null) return state.selected;
    if (state.selected?.id == id) return state.selected;
    for (final skill in state.skills) {
      if (skill.id == id) return skill;
    }
    return null;
  }

  void _showList() {
    setState(() {
      _page = _SkillPage.list;
      _activeSkillId = null;
      _returnToDetailAfterEdit = false;
    });
  }

  void _showDetail(ManagedSkill skill) {
    setState(() {
      _page = _SkillPage.detail;
      _activeSkillId = skill.id;
      _returnToDetailAfterEdit = false;
    });
  }

  Widget _buildBody(
    SkillsState state,
    List<GatewayInfo> gateways, {
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    if (_page == _SkillPage.list) {
      return RefreshIndicator(
        onRefresh: () => _refreshSkills(gateways),
        child: _buildSkillsList(
          state,
          gateways,
          unavailableGateway: unavailableGateway,
          compact: compact,
        ),
      );
    }

    if (_page == _SkillPage.edit) {
      final skill = _activeSkillId == null ? null : _activeSkill(state);
      if (skill == null && state.selectedScope == null) {
        return _buildSkillsList(
          state,
          gateways,
          unavailableGateway: unavailableGateway,
          compact: compact,
        );
      }
      return _SkillEditPage(
        initial: skill,
        isSaving:
            state.isSaving ||
            (skill != null && state.busySkillIds.contains(skill.id)),
        onCancel: () => skill != null && _returnToDetailAfterEdit
            ? _showDetail(skill)
            : _showList(),
        onSave: (draft) => _saveSkill(draft, initial: skill),
      );
    }

    final skill = _activeSkill(state);
    if (skill == null) {
      return _buildSkillsList(
        state,
        gateways,
        unavailableGateway: unavailableGateway,
        compact: compact,
      );
    }

    return _SkillDetailPage(
      skill: skill,
      isLoadingBody: state.busySkillIds.contains(skill.id),
      canEdit: skill.writable && !state.isScopeReadOnly,
      onBack: _showList,
      onEdit: () => _openEditor(initial: skill, returnToDetail: true),
    );
  }

  Widget _buildSkillsList(
    SkillsState state,
    List<GatewayInfo> gateways, {
    GatewayInfo? unavailableGateway,
    required bool compact,
  }) {
    final filteredSkills = _filtered(state.skills);
    final showUnavailablePanel = unavailableGateway != null;
    final showLoadingPanel =
        !showUnavailablePanel && state.isLoading && state.skills.isEmpty;
    final showEmptyPanel =
        !showUnavailablePanel && !showLoadingPanel && filteredSkills.isEmpty;
    final hasMobileScopeSelector = compact && gateways.isNotEmpty;
    if (!showUnavailablePanel && (showLoadingPanel || showEmptyPanel)) {
      return _buildSkillsStateList(
        state,
        gateways,
        compact: compact,
        showLoading: showLoadingPanel,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = compact ? 16.0 : 28.0;
        const cardGap = 14.0;
        const minCardWidth = 560.0;
        final contentWidth = constraints.maxWidth - padding * 2;
        final columnCount =
            !compact && contentWidth >= minCardWidth * 2 + cardGap ? 2 : 1;
        final cardWidth = columnCount == 2
            ? (contentWidth - cardGap) / 2
            : contentWidth;
        final inlineControls = !compact && cardWidth >= 760;
        final cardMainAxisExtent = _skillCardMainAxisExtent(
          context,
          inlineControls: inlineControls,
        );

        final topItems = <Widget>[
          if (hasMobileScopeSelector) ...[
            GatewayMobileSelectorButton(
              gateways: gateways,
              selectedGatewayId: state.selectedScope?.gatewayId,
              capability: 'skills',
              errorGatewayId:
                  state.errorGatewayId ?? unavailableGateway?.gatewayId,
              onSelected: _selectGateway,
            ),
            const SizedBox(height: 18),
          ],
          _Header(
            isLoading: state.isLoading,
            isReadOnly: state.isScopeReadOnly || state.selectedScope == null,
            hasGatewayIssue:
                showUnavailablePanel || state.errorGatewayId != null,
            compact: compact && widget.showAppBar,
            onCreate: () => _openEditor(),
            onRefresh: () => unawaited(_refreshSkills(gateways)),
          ),
          const SizedBox(height: 18),
          _Toolbar(
            controller: _searchController,
            filter: _statusFilter,
            sourceFilter: _sourceFilter,
            compact: compact,
            total: state.skills.length,
            enabled: state.skills.where((skill) => skill.enabled).length,
            onFilterChanged: (filter) => setState(() => _statusFilter = filter),
            onSourceFilterChanged: (filter) =>
                setState(() => _sourceFilter = filter),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          if (showUnavailablePanel)
            SizedBox(
              height: gatewayUnavailablePanelHeight(context, compact),
              child: GatewayUnavailablePanel(
                title: gatewayUnavailableTitle(
                  context,
                  unavailableGateway,
                  capability: 'skills',
                  capabilityNameZh: '技能管理',
                  capabilityNameEn: 'skill management',
                ),
                message: _localized(
                  context,
                  'Reconnect the gateway to refresh skills.',
                  '连接恢复后，技能列表会自动刷新。',
                ),
                footnote: _localized(
                  context,
                  'No skill request will be sent.',
                  '当前不会发起技能请求',
                ),
              ),
            ),
        ];

        if (showUnavailablePanel) {
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(padding),
                sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
              ),
            ],
          );
        }

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                left: padding,
                top: padding,
                right: padding,
              ),
              sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                left: padding,
                right: padding,
                bottom: padding,
              ),
              sliver: columnCount == 2
                  ? SliverGrid.builder(
                      itemCount: filteredSkills.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: cardGap,
                        crossAxisSpacing: cardGap,
                        mainAxisExtent: cardMainAxisExtent,
                      ),
                      itemBuilder: (context, index) => _SkillCard(
                        skill: filteredSkills[index],
                        isBusy: state.busySkillIds.contains(
                          filteredSkills[index].id,
                        ),
                        isToggleBusy: state.togglingSkillIds.contains(
                          filteredSkills[index].id,
                        ),
                        readOnlyScope: state.isScopeReadOnly,
                        inlineControls: inlineControls,
                        onToggle: _toggleSkill,
                        onOpen: _openDetail,
                        onEdit: _editSkill,
                        onDelete: _deleteSkill,
                      ),
                    )
                  : SliverList.builder(
                      itemCount: filteredSkills.length,
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.only(
                          bottom: index == filteredSkills.length - 1
                              ? 0
                              : cardGap,
                        ),
                        child: _SkillCard(
                          skill: filteredSkills[index],
                          isBusy: state.busySkillIds.contains(
                            filteredSkills[index].id,
                          ),
                          isToggleBusy: state.togglingSkillIds.contains(
                            filteredSkills[index].id,
                          ),
                          readOnlyScope: state.isScopeReadOnly,
                          inlineControls: inlineControls,
                          onToggle: _toggleSkill,
                          onOpen: _openDetail,
                          onEdit: _editSkill,
                          onDelete: _deleteSkill,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkillsStateList(
    SkillsState state,
    List<GatewayInfo> gateways, {
    required bool compact,
    required bool showLoading,
  }) {
    final padding = compact ? 16.0 : 28.0;
    final topItems = <Widget>[
      if (compact && gateways.isNotEmpty) ...[
        GatewayMobileSelectorButton(
          gateways: gateways,
          selectedGatewayId: state.selectedScope?.gatewayId,
          capability: 'skills',
          errorGatewayId: state.errorGatewayId,
          onSelected: _selectGateway,
        ),
        const SizedBox(height: 18),
      ],
      _Header(
        isLoading: state.isLoading,
        isReadOnly: state.isScopeReadOnly || state.selectedScope == null,
        hasGatewayIssue: state.errorGatewayId != null,
        compact: compact && widget.showAppBar,
        onCreate: () => _openEditor(),
        onRefresh: () => unawaited(_refreshSkills(gateways)),
      ),
      const SizedBox(height: 18),
      _Toolbar(
        controller: _searchController,
        filter: _statusFilter,
        sourceFilter: _sourceFilter,
        compact: compact,
        total: state.skills.length,
        enabled: state.skills.where((skill) => skill.enabled).length,
        onFilterChanged: (filter) => setState(() => _statusFilter = filter),
        onSourceFilterChanged: (filter) =>
            setState(() => _sourceFilter = filter),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 18),
    ];

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(left: padding, top: padding, right: padding),
          sliver: SliverList(delegate: SliverChildListDelegate(topItems)),
        ),
        SliverPadding(
          padding: EdgeInsets.only(
            left: padding,
            right: padding,
            bottom: padding,
          ),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: showLoading ? const _LoadingPanel() : const _EmptyPanel(),
          ),
        ),
      ],
    );
  }

  Future<void> _selectGateway(String gatewayId) async {
    final gateways =
        ref.read(gatewayListProvider).valueOrNull ?? const <GatewayInfo>[];
    final gateway = gatewayById(gateways, gatewayId);
    if (gateway != null && gatewayUnavailableFor(gateway, 'skills')) {
      _markSkillsGatewayUnavailable(
        orderGatewaysForSelection(
          gateways,
          'skills',
          currentGatewayId: gatewayId,
        ),
        gateway,
      );
      return;
    }
    await ref.read(skillsControllerProvider.notifier).selectGateway(gatewayId);
    if (mounted) _showList();
  }

  GatewayInfo? _selectedUnavailableGateway(
    List<GatewayInfo> gateways,
    SkillsState state,
  ) {
    final gateway = gatewayById(gateways, state.selectedScope?.gatewayId);
    if (gateway == null || !gatewayUnavailableFor(gateway, 'skills')) {
      return null;
    }
    return gateway;
  }

  void _markSkillsGatewayUnavailable(
    List<GatewayInfo> gateways,
    GatewayInfo gateway,
  ) {
    ref
        .read(skillsControllerProvider.notifier)
        .selectUnavailableGateway(
          gateways,
          gateway.gatewayId,
          gatewayUnavailableStateMessage(context, gateway),
        );
  }

  void _openEditor({ManagedSkill? initial, bool returnToDetail = false}) {
    setState(() {
      _page = _SkillPage.edit;
      _activeSkillId = initial?.id;
      _returnToDetailAfterEdit = returnToDetail;
    });
  }

  Future<void> _saveSkill(SkillDraft draft, {ManagedSkill? initial}) async {
    final notifier = ref.read(skillsControllerProvider.notifier);
    try {
      if (initial == null) {
        await notifier.create(draft);
      } else {
        await notifier.update(initial.id, draft);
      }
      final savedSkill = ref.read(skillsControllerProvider).selected;
      if (mounted) {
        setState(() {
          _page = _SkillPage.detail;
          _activeSkillId = savedSkill?.id ?? initial?.id;
          _returnToDetailAfterEdit = false;
        });
      }
      if (mounted) {
        showAppSnackBar(
          context,
          initial == null
              ? context.l10n.skillsCreated
              : context.l10n.skillsSaved,
        );
      }
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  void _openDetail(ManagedSkill skill) {
    _showDetail(skill);
    unawaited(ref.read(skillsControllerProvider.notifier).loadDetail(skill.id));
  }

  Future<void> _editSkill(ManagedSkill skill) async {
    final detail = await ref
        .read(skillsControllerProvider.notifier)
        .loadDetail(skill.id);
    if (!mounted || detail == null) return;
    _openEditor(initial: detail);
  }

  Future<void> _toggleSkill(ManagedSkill skill, bool enabled) async {
    try {
      await ref
          .read(skillsControllerProvider.notifier)
          .setEnabled(skill.id, enabled);
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  Future<void> _deleteSkill(ManagedSkill skill) async {
    final skillDirectory = _skillDirectoryPath(skill);
    final message = _localized(
      context,
      'This will delete skill directory $skillDirectory. This action cannot be undone.\nContinue?',
      '将删除技能目录 $skillDirectory，此操作不可撤销。\n是否继续？',
    );
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.skillsDeleteTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await ref.read(skillsControllerProvider.notifier).delete(skill.id);
      if (mounted && _activeSkillId == skill.id) _showList();
      if (mounted) {
        showAppSnackBar(context, context.l10n.skillsDeleted);
      }
    } catch (_) {
      // The provider listener displays the API error.
    }
  }

  String _skillDirectoryPath(ManagedSkill skill) {
    final displayPath = skill.displayPath.trim();
    if (displayPath.isEmpty) return skill.name;
    final normalized = displayPath.replaceAll('\\', '/');
    const suffix = '/SKILL.md';
    if (normalized.endsWith(suffix)) {
      return normalized.substring(0, normalized.length - suffix.length);
    }
    return normalized;
  }
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}

double _skillCardMainAxisExtent(
  BuildContext context, {
  required bool inlineControls,
}) {
  final textTheme = Theme.of(context).textTheme;
  final typographyScale = math.max(
    math.max((textTheme.titleSmall?.fontSize ?? 14) / 14, 1),
    math.max((textTheme.bodySmall?.fontSize ?? 14) / 14, 1),
  );
  final typographyExtra = ((typographyScale - 1) * 180)
      .clamp(0.0, 120.0)
      .toDouble();
  return inlineControls
      ? 196.0 + typographyExtra * 0.45
      : 220.0 + typographyExtra;
}

class _Header extends StatelessWidget {
  final bool isLoading;
  final bool isReadOnly;
  final bool hasGatewayIssue;
  final bool compact;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  const _Header({
    required this.isLoading,
    required this.isReadOnly,
    required this.hasGatewayIssue,
    required this.compact,
    required this.onCreate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.navSkills,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.skillsPageSubtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: isLoading || hasGatewayIssue ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: context.l10n.skillsRefresh,
            ),
            FilledButton.icon(
              onPressed: isReadOnly || hasGatewayIssue ? null : onCreate,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.skillsNewSkill),
            ),
          ],
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  final TextEditingController controller;
  final _SkillStatusFilter filter;
  final _SkillSourceFilter sourceFilter;
  final bool compact;
  final int total;
  final int enabled;
  final ValueChanged<_SkillStatusFilter> onFilterChanged;
  final ValueChanged<_SkillSourceFilter> onSourceFilterChanged;
  final ValueChanged<String> onChanged;

  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.sourceFilter,
    required this.compact,
    required this.total,
    required this.enabled,
    required this.onFilterChanged,
    required this.onSourceFilterChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final searchTextStyle = theme.textTheme.bodyMedium;
    final filterTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final disabled = total - enabled;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = compact
              ? constraints.maxWidth
              : math.min(430.0, constraints.maxWidth);
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  style: searchTextStyle,
                  decoration: InputDecoration(
                    hintText: context.l10n.searchSkills,
                    hintStyle: searchTextStyle?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SegmentedButton<_SkillStatusFilter>(
                key: const ValueKey('skills_status_filter'),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(filterTextStyle),
                ),
                selected: {filter},
                onSelectionChanged: (selected) =>
                    onFilterChanged(selected.first),
                segments: [
                  ButtonSegment(
                    value: _SkillStatusFilter.all,
                    label: Text('${context.l10n.skillsStatusAll} $total'),
                  ),
                  ButtonSegment(
                    value: _SkillStatusFilter.enabled,
                    label: Text('${context.l10n.skillsStatusEnabled} $enabled'),
                  ),
                  ButtonSegment(
                    value: _SkillStatusFilter.disabled,
                    label: Text(
                      '${context.l10n.skillsStatusDisabled} $disabled',
                    ),
                  ),
                ],
              ),
              SegmentedButton<_SkillSourceFilter>(
                key: const ValueKey('skills_source_filter'),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(filterTextStyle),
                ),
                selected: {sourceFilter},
                onSelectionChanged: (selected) =>
                    onSourceFilterChanged(selected.first),
                segments: [
                  ButtonSegment(
                    value: _SkillSourceFilter.all,
                    label: Text(context.l10n.skillsSourceAll),
                  ),
                  ButtonSegment(
                    value: _SkillSourceFilter.managed,
                    label: Text(context.l10n.skillsSourceManaged),
                  ),
                  ButtonSegment(
                    value: _SkillSourceFilter.external,
                    label: Text(context.l10n.skillsSourceExternal),
                  ),
                  ButtonSegment(
                    value: _SkillSourceFilter.readonly,
                    label: Text(context.l10n.skillsSourceReadonly),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final ManagedSkill skill;
  final bool isBusy;
  final bool isToggleBusy;
  final bool readOnlyScope;
  final bool inlineControls;
  final void Function(ManagedSkill skill, bool enabled) onToggle;
  final ValueChanged<ManagedSkill> onOpen;
  final ValueChanged<ManagedSkill> onEdit;
  final ValueChanged<ManagedSkill> onDelete;

  const _SkillCard({
    required this.skill,
    required this.isBusy,
    required this.isToggleBusy,
    required this.readOnlyScope,
    required this.inlineControls,
    required this.onToggle,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = skill.enabled ? colorScheme.primary : colorScheme.outline;
    final sourceTagColor = colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.72,
    );
    final sourceTagForeground = colorScheme.onSurfaceVariant;
    final skillTitleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final skillBodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final actionButtonStyle = OutlinedButton.styleFrom(
      textStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      minimumSize: const Size(78, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
    );
    final pathStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final controls = _SkillCardControls(
      key: ValueKey('skill_card_controls_${skill.id}'),
      skill: skill,
      isBusy: isBusy,
      isToggleBusy: isToggleBusy,
      readOnlyScope: readOnlyScope,
      inline: inlineControls,
      actionButtonStyle: actionButtonStyle,
      onToggle: onToggle,
      onEdit: onEdit,
      onDelete: onDelete,
    );
    final body = Column(
      key: ValueKey('skill_card_body_${skill.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(skill.displayName, style: skillTitleStyle),
            if (skill.sourceLabel.trim().isNotEmpty)
              _Tag(
                label: skill.sourceLabel,
                color: sourceTagColor,
                foreground: sourceTagForeground,
              ),
            if (skill.hasConflict)
              _Tag(
                label: context.l10n.skillsConflict,
                color: colorScheme.errorContainer,
                foreground: colorScheme.onErrorContainer,
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          skill.displayDescription,
          key: ValueKey('skill_card_description_${skill.id}'),
          style: skillBodyStyle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                skill.displayPath,
                key: ValueKey('skill_card_path_${skill.id}'),
                style: pathStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
    final icon = Container(
      key: ValueKey('skill_card_icon_${skill.id}'),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.bolt, color: accent),
    );

    return Card(
      key: ValueKey('skill_card_${skill.id}'),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: !isBusy ? () => onOpen(skill) : null,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 16,
              bottom: 16,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(3),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: inlineControls
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 14),
                        Expanded(child: body),
                        const SizedBox(width: 14),
                        SizedBox(width: 180, child: controls),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 14),
                            Expanded(child: body),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: controls,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillCardControls extends StatelessWidget {
  final ManagedSkill skill;
  final bool isBusy;
  final bool isToggleBusy;
  final bool readOnlyScope;
  final bool inline;
  final ButtonStyle actionButtonStyle;
  final void Function(ManagedSkill skill, bool enabled) onToggle;
  final ValueChanged<ManagedSkill> onEdit;
  final ValueChanged<ManagedSkill> onDelete;

  const _SkillCardControls({
    super.key,
    required this.skill,
    required this.isBusy,
    required this.isToggleBusy,
    required this.readOnlyScope,
    required this.inline,
    required this.actionButtonStyle,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = Row(
      key: ValueKey('skill_card_status_${skill.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: skill.enabled ? colorScheme.primary : colorScheme.outline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          skill.enabled
              ? context.l10n.skillsStatusEnabled
              : context.l10n.skillsStatusDisabled,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final switcher = Transform.scale(
      scale: 0.86,
      alignment: Alignment.centerRight,
      child: Switch(
        value: skill.enabled,
        onChanged: readOnlyScope || isToggleBusy
            ? null
            : (enabled) => onToggle(skill, enabled),
      ),
    );
    final actions = inline
        ? Column(
            key: ValueKey('skill_card_actions_${skill.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _editButton(context),
              const SizedBox(height: 8),
              _deleteButton(context),
            ],
          )
        : Row(
            key: ValueKey('skill_card_actions_${skill.id}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _editButton(context),
              const SizedBox(width: 8),
              _deleteButton(context),
            ],
          );

    if (inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [status, switcher],
              ),
            ),
          ),
          const SizedBox(height: 10),
          actions,
        ],
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [status, switcher, const SizedBox(width: 8), actions],
      ),
    );
  }

  Widget _editButton(BuildContext context) {
    return OutlinedButton.icon(
      style: actionButtonStyle,
      onPressed: skill.writable && !readOnlyScope && !isBusy
          ? () => onEdit(skill)
          : null,
      icon: const Icon(Icons.edit_outlined),
      label: Text(context.l10n.edit),
    );
  }

  Widget _deleteButton(BuildContext context) {
    return OutlinedButton.icon(
      style: actionButtonStyle,
      onPressed: skill.deletable && !readOnlyScope && !isBusy
          ? () => onDelete(skill)
          : null,
      icon: const Icon(Icons.delete_outline),
      label: Text(context.l10n.delete),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? foreground;

  const _Tag({required this.label, this.color, this.foreground});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground ?? colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SkillDetailPage extends StatelessWidget {
  final ManagedSkill skill;
  final bool isLoadingBody;
  final bool canEdit;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const _SkillDetailPage({
    required this.skill,
    required this.isLoadingBody,
    required this.canEdit,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final trigger = skill.displayTrigger?.trim() ?? '';
    final bodyText = skill.displayBody ?? skill.content ?? '';

    return _SkillSubpageScaffold(
      title: _localized(context, 'Skill Detail', '技能详情'),
      actionIcon: canEdit ? Icons.edit_outlined : null,
      actionLabel: canEdit ? _localized(context, 'Edit', '编辑') : null,
      onAction: canEdit ? onEdit : null,
      onBack: onBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final definition = _SkillInfoSection(
            title: _localized(context, 'Skill Definition', '技能定义'),
            child: _SkillKeyValueList(
              rows: [
                (context.l10n.skillsFieldName, skill.name),
                (context.l10n.skillsFieldCategory, skill.category),
                (_localized(context, 'Source', '来源'), skill.sourceLabel),
                (
                  _localized(context, 'Status', '状态'),
                  _localized(
                    context,
                    skill.enabled ? 'Enabled' : 'Disabled',
                    skill.enabled ? '已启用' : '已禁用',
                  ),
                ),
                (_localized(context, 'Path', '路径'), skill.displayPath),
              ],
            ),
          );
          final usage = _SkillInfoSection(
            title: _localized(context, 'Usage', '使用条件'),
            child: _SkillKeyValueList(
              rows: [
                (
                  context.l10n.skillsFieldTrigger,
                  trigger.isEmpty ? _localized(context, 'None', '无') : trigger,
                ),
                (
                  _localized(context, 'Writable', '可编辑'),
                  skill.writable
                      ? _localized(context, 'Yes', '是')
                      : _localized(context, 'No', '否'),
                ),
                (
                  _localized(context, 'Deletable', '可删除'),
                  skill.deletable
                      ? _localized(context, 'Yes', '是')
                      : _localized(context, 'No', '否'),
                ),
              ],
            ),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SkillDetailPanel(
                key: const ValueKey('skill_detail_basic_info'),
                title: _localized(context, 'Basic Info', '基本信息'),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: definition),
                          const SizedBox(width: 24),
                          Expanded(child: usage),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          definition,
                          const SizedBox(height: 18),
                          usage,
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              _SkillDetailPanel(
                title: context.l10n.skillsFieldDescription,
                child: SelectableText(skill.displayDescription),
              ),
              const SizedBox(height: 16),
              _SkillDetailPanel(
                title: context.l10n.skillsSkillMdBody,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: bodyText.trim().isEmpty && isLoadingBody
                      ? _SkillBodyLoading()
                      : SelectableText(
                          bodyText,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SkillBodyLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _localized(context, 'Loading SKILL.md...', '正在加载 SKILL.md...'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillEditPage extends StatefulWidget {
  final ManagedSkill? initial;
  final bool isSaving;
  final ValueChanged<SkillDraft> onSave;
  final VoidCallback onCancel;

  const _SkillEditPage({
    required this.initial,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<_SkillEditPage> createState() => _SkillEditPageState();
}

class _SkillEditPageState extends State<_SkillEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _triggerController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    final skill = widget.initial;
    _nameController = TextEditingController(text: skill?.name ?? '');
    _categoryController = TextEditingController(
      text: skill?.category ?? 'general',
    );
    _descriptionController = TextEditingController(
      text: skill?.description ?? '',
    );
    _triggerController = TextEditingController(text: skill?.trigger ?? '');
    _bodyController = TextEditingController(
      text:
          skill?.body ??
          '## Purpose\n\n'
              'Describe what this skill does and when to use it.\n\n'
              '## Use When\n\n'
              '- Users ask to ...\n'
              '- The task requires ...\n\n'
              '## Workflow\n\n'
              "1. Confirm the user's goal.\n"
              '2. Gather required inputs.\n'
              '3. Execute the skill-specific steps.\n'
              '4. Return concise results.\n\n'
              '## Guardrails\n\n'
              '- Do not expose secrets.\n'
              '- Ask before destructive operations.\n',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _triggerController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.initial == null
        ? context.l10n.skillsNewSkill
        : context.l10n.skillsEditTitle;
    final l10n = context.l10n;

    return _SkillSubpageScaffold(
      title: title,
      actionIcon: widget.initial == null ? Icons.add : Icons.save_outlined,
      actionLabel: widget.initial == null ? l10n.create : l10n.save,
      onAction: widget.isSaving ? null : _submit,
      onBack: widget.onCancel,
      isBusy: widget.isSaving,
      maxContentWidth: 1180,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SkillDetailPanel(
              title: _localized(context, 'Basic Info', '基础信息'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SkillFormGrid(
                    children: [
                      _SkillLabeledField(
                        label: l10n.skillsFieldName,
                        helper: _localized(
                          context,
                          'Required. Used as the skill directory name, for example my-skill.',
                          '必填。将作为技能目录名，例如 my-skill。',
                        ),
                        child: TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: 'my-skill',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _validatePathPart(value, l10n),
                        ),
                      ),
                      _SkillLabeledField(
                        label: l10n.skillsFieldCategory,
                        helper: _localized(
                          context,
                          'Default general. Used for filtering and display.',
                          '默认 general，用于筛选和展示。',
                        ),
                        child: TextFormField(
                          controller: _categoryController,
                          decoration: const InputDecoration(
                            hintText: 'general',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _validatePathPart(value, l10n),
                        ),
                      ),
                      _SkillLabeledField(
                        label: l10n.skillsFieldTrigger,
                        helper: _localized(
                          context,
                          'Optional. Explains when the agent should use this skill.',
                          '可选。说明 Agent 什么时候应该启用这个技能。',
                        ),
                        child: TextFormField(
                          controller: _triggerController,
                          decoration: const InputDecoration(
                            hintText: 'Use when...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SkillLabeledField(
                    label: l10n.skillsFieldDescription,
                    child: TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        hintText: _localized(
                          context,
                          'One sentence describing what this skill does.',
                          '一句话说明这个技能做什么、什么时候使用。',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? l10n.skillsDescriptionRequired
                          : null,
                    ),
                  ),
                  if (widget.initial == null) ...[
                    const SizedBox(height: 12),
                    _SkillCreatePathPreview(nameController: _nameController),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SkillDetailPanel(
              title: l10n.skillsSkillMdBody,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.initial == null) ...[
                    Text(
                      _localized(
                        context,
                        'The default template keeps the required structure. Saving generates SKILL.md.',
                        '默认模板保留必要结构，保存时生成 SKILL.md。',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _bodyController,
                    minLines: 10,
                    maxLines: 18,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _validatePathPart(String? value, AppLocalizations l10n) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return l10n.skillsFieldRequired;
    if (text == '.' ||
        text == '..' ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)) {
      return l10n.skillsPathPartInvalid;
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(
      SkillDraft(
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim(),
        trigger: _triggerController.text.trim(),
        body: _bodyController.text,
      ),
    );
  }
}

class _SkillSubpageScaffold extends StatelessWidget {
  final String title;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onBack;
  final bool isBusy;
  final double? maxContentWidth;
  final Widget child;

  const _SkillSubpageScaffold({
    required this.title,
    required this.actionIcon,
    required this.actionLabel,
    required this.onAction,
    required this.onBack,
    required this.child,
    this.isBusy = false,
    this.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SkillSubpageAppBar(
          title: title,
          actionIcon: actionIcon,
          actionLabel: actionLabel,
          onAction: onAction,
          onBack: onBack,
          isBusy: isBusy,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = maxContentWidth == null
                  ? child
                  : Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth!),
                        child: child,
                      ),
                    );
              return SingleChildScrollView(
                padding: EdgeInsets.all(constraints.maxWidth < 600 ? 16 : 28),
                child: content,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkillSubpageAppBar extends StatelessWidget {
  final String title;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onBack;
  final bool isBusy;

  const _SkillSubpageAppBar({
    required this.title,
    required this.actionIcon,
    required this.actionLabel,
    required this.onAction,
    required this.onBack,
    required this.isBusy,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAction = actionIcon != null && actionLabel != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: kToolbarHeight,
        child: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
          title: Text(title),
          centerTitle: true,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: hasAction
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _SkillAppBarAction(
                      icon: actionIcon!,
                      label: actionLabel!,
                      onPressed: onAction,
                      busy: isBusy,
                    ),
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _SkillAppBarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  const _SkillAppBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionIcon = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          )
        : Icon(icon, size: 20);

    return TextButton.icon(
      key: const ValueKey('skill_app_bar_action'),
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        disabledForegroundColor: colorScheme.onSurfaceVariant,
        textStyle: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      icon: actionIcon,
      label: Text(label),
    );
  }
}

class _SkillFormGrid extends StatelessWidget {
  final List<Widget> children;

  const _SkillFormGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(height: 14),
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 11, child: children[0]),
            const SizedBox(width: 14),
            Expanded(flex: 8, child: children[1]),
            const SizedBox(width: 14),
            Expanded(flex: 10, child: children[2]),
          ],
        );
      },
    );
  }
}

class _SkillLabeledField extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;

  const _SkillLabeledField({
    required this.label,
    required this.child,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        child,
        if (helper != null) ...[
          const SizedBox(height: 8),
          Text(
            helper!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SkillCreatePathPreview extends StatelessWidget {
  final TextEditingController nameController;

  const _SkillCreatePathPreview({required this.nameController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: nameController,
      builder: (context, value, _) {
        final name = value.text.trim().isEmpty ? '<name>' : value.text.trim();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text.rich(
            TextSpan(
              text: _localized(context, 'Created path: ', '创建后路径：'),
              children: [
                TextSpan(
                  text: '~/.agents/skills/$name/SKILL.md',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}

class _SkillInfoSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SkillInfoSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _SkillDetailPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _SkillDetailPanel({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SkillKeyValueList extends StatelessWidget {
  final List<(String, String)> rows;

  const _SkillKeyValueList({required this.rows});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.$1,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel();

  @override
  Widget build(BuildContext context) {
    return EmptyStatePanel(
      icon: Icons.extension_outlined,
      title: context.l10n.noSkillsAvailable,
    );
  }
}
