import 'dart:async';

import 'package:client/models/gateway_info.dart';
import 'package:client/models/managed_skill.dart';
import 'package:client/models/skillhub_item.dart';
import 'package:client/providers/database_providers.dart';
import 'package:client/providers/gateway_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/skills_provider.dart'
    show skillsControllerProvider;
import 'package:client/services/skillhub_api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const skillHubReceiveTimeoutUiCode = 'skillhub_receive_timeout';
const skillHubNetworkErrorUiCode = 'skillhub_network_error';

const _unset = Object();

final skillHubApiServiceProvider = Provider<SkillHubApiService>((ref) {
  return SkillHubApiService();
});

final skillHubControllerProvider =
    StateNotifierProvider<SkillHubController, SkillHubState>((ref) {
      return SkillHubController(ref.watch(skillHubApiServiceProvider), ref);
    });

Future<void> refreshSkillCaches(Ref ref) async {
  try {
    final gateways = await ref.read(onlineGatewayListProvider.future);
    final candidates = gateways.where(_canRefreshSkillCache).toList();
    if (candidates.isEmpty) return;

    final cache = ref.read(skillCacheRepositoryProvider);
    final locale = ref.read(localeProvider)?.languageCode ?? 'en';
    final refreshedSkills = <String, List<ManagedSkill>>{};
    await Future.wait(
      candidates.map((gateway) async {
        try {
          refreshedSkills[gateway.gatewayId] = await cache.syncGateway(
            _skillScopeForGateway(gateway),
            locale,
          );
        } catch (error) {
          debugPrint(
            '[SkillHub] ⚠️ refreshSkillCaches failed: gateway=${gateway.gatewayId} error=$error',
          );
        }
      }),
    );
    ref
        .read(skillsControllerProvider.notifier)
        .applyExternalRefresh(refreshedSkills);
  } catch (error) {
    debugPrint('[SkillHub] ⚠️ refreshSkillCaches skipped: error=$error');
  }
}

@immutable
class SkillHubState {
  final List<SkillHubItem> items;
  final SkillHubItem? selected;
  final String? nextCursor;
  final int total;
  final bool isLoading;
  final bool isLoadingMore;
  final bool isDetailLoading;
  final Set<String> installingIds;
  final Set<String> installedIds;
  final Set<String> skillHubInstalledSlugs;
  final Map<String, String> skillHubInstallPaths;
  final Map<String, String> pendingInstallIds;
  final Map<String, String> installMessages;
  final Map<String, String> installStatuses;
  final List<SkillHubFallbackGateway> fallbackGateways;
  final String? query;
  final String? category;
  final String? tag;
  final bool? featured;
  final String? gatewayType;
  final String? errorMessage;
  final String? loadMoreError;

  const SkillHubState({
    this.items = const [],
    this.selected,
    this.nextCursor,
    this.total = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.isDetailLoading = false,
    this.installingIds = const {},
    this.installedIds = const {},
    this.skillHubInstalledSlugs = const {},
    this.skillHubInstallPaths = const {},
    this.pendingInstallIds = const {},
    this.installMessages = const {},
    this.installStatuses = const {},
    this.fallbackGateways = const [],
    this.query,
    this.category,
    this.tag,
    this.featured,
    this.gatewayType,
    this.errorMessage,
    this.loadMoreError,
  });

  SkillHubState copyWith({
    List<SkillHubItem>? items,
    SkillHubItem? selected,
    bool clearSelected = false,
    String? nextCursor,
    bool clearNextCursor = false,
    int? total,
    bool? isLoading,
    bool? isLoadingMore,
    bool? isDetailLoading,
    Set<String>? installingIds,
    Set<String>? installedIds,
    Set<String>? skillHubInstalledSlugs,
    Map<String, String>? skillHubInstallPaths,
    Map<String, String>? pendingInstallIds,
    Map<String, String>? installMessages,
    Map<String, String>? installStatuses,
    List<SkillHubFallbackGateway>? fallbackGateways,
    Object? query = _unset,
    Object? category = _unset,
    Object? tag = _unset,
    Object? featured = _unset,
    Object? gatewayType = _unset,
    String? errorMessage,
    bool clearError = false,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return SkillHubState(
      items: items ?? this.items,
      selected: clearSelected ? null : (selected ?? this.selected),
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      total: total ?? this.total,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isDetailLoading: isDetailLoading ?? this.isDetailLoading,
      installingIds: installingIds ?? this.installingIds,
      installedIds: installedIds ?? this.installedIds,
      skillHubInstalledSlugs:
          skillHubInstalledSlugs ?? this.skillHubInstalledSlugs,
      skillHubInstallPaths: skillHubInstallPaths ?? this.skillHubInstallPaths,
      pendingInstallIds: pendingInstallIds ?? this.pendingInstallIds,
      installMessages: installMessages ?? this.installMessages,
      installStatuses: installStatuses ?? this.installStatuses,
      fallbackGateways: fallbackGateways ?? this.fallbackGateways,
      query: identical(query, _unset) ? this.query : query as String?,
      category: identical(category, _unset)
          ? this.category
          : category as String?,
      tag: identical(tag, _unset) ? this.tag : tag as String?,
      featured: identical(featured, _unset) ? this.featured : featured as bool?,
      gatewayType: identical(gatewayType, _unset)
          ? this.gatewayType
          : gatewayType as String?,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class SkillHubController extends StateNotifier<SkillHubState> {
  SkillHubController(this._api, [this._ref]) : super(const SkillHubState());

  final SkillHubApiService _api;
  final Ref? _ref;

  Future<void> load({
    String? query,
    String? category,
    String? tag,
    bool? featured,
    String? gatewayType,
    int? limit,
    String? cursor,
  }) async {
    state = state.copyWith(
      isLoading: true,
      query: query,
      category: category,
      tag: tag,
      featured: featured,
      gatewayType: gatewayType,
      clearError: true,
      isLoadingMore: false,
      clearLoadMoreError: true,
    );
    try {
      final result = await _api.listSkills(
        query: query,
        category: category,
        tag: tag,
        featured: featured,
        gatewayType: gatewayType,
        limit: limit,
        cursor: cursor,
      );
      state = state.copyWith(
        items: result.items,
        nextCursor: result.nextCursor,
        clearNextCursor: result.nextCursor == null,
        total: result.total,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _errorMessage(e));
    }
  }

  Future<void> loadMore({int? limit}) async {
    final cursor = state.nextCursor;
    if (state.isLoading || state.isLoadingMore || cursor == null) return;

    final query = state.query;
    final category = state.category;
    final tag = state.tag;
    final featured = state.featured;
    final gatewayType = state.gatewayType;

    state = state.copyWith(
      isLoadingMore: true,
      clearError: true,
      clearLoadMoreError: true,
    );
    try {
      final result = await _api.listSkills(
        query: query,
        category: category,
        tag: tag,
        featured: featured,
        gatewayType: gatewayType,
        limit: limit,
        cursor: cursor,
      );
      if (state.query != query ||
          state.category != category ||
          state.tag != tag ||
          state.featured != featured ||
          state.gatewayType != gatewayType) {
        return;
      }
      final existingIds = state.items.map((item) => item.id).toSet();
      final appendedItems = [
        ...state.items,
        ...result.items.where((item) => !existingIds.contains(item.id)),
      ];
      state = state.copyWith(
        items: appendedItems,
        nextCursor: result.nextCursor,
        clearNextCursor: result.nextCursor == null,
        total: appendedItems.length,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        loadMoreError: _errorMessage(e),
      );
    }
  }

  Future<void> loadDetail(String id) async {
    state = state.copyWith(isDetailLoading: true, clearError: true);
    try {
      final detail = await _api.getSkill(id, gatewayType: state.gatewayType);
      state = state.copyWith(selected: detail, isDetailLoading: false);
    } catch (e) {
      state = state.copyWith(
        isDetailLoading: false,
        errorMessage: _errorMessage(e),
      );
    }
  }

  Future<bool> install(
    SkillHubItem item, {
    String? gatewayId,
    String? gatewayType,
    String? installMode,
  }) async {
    if (state.installingIds.contains(item.id)) return false;
    if (item.compatibility == 'incompatible') {
      state = state.copyWith(errorMessage: '当前 Gateway 不兼容，无法安装。');
      return false;
    }

    state = state.copyWith(
      installingIds: {...state.installingIds, item.id},
      clearError: true,
    );
    try {
      final result = await _api.installSkill(
        item,
        gatewayId: gatewayId,
        gatewayType: gatewayType ?? state.gatewayType,
        installMode: installMode ?? 'auto',
      );
      final installedIds = {...state.installedIds};
      final skillHubInstalledSlugs = {...state.skillHubInstalledSlugs};
      if (result.installed) {
        installedIds.add(item.id);
        skillHubInstalledSlugs.add(_normalizeSkillHubSlug(item.slug));
      }
      final pendingInstallIds = {...state.pendingInstallIds};
      if (!result.installed && result.installId.isNotEmpty) {
        pendingInstallIds[result.installId] = item.id;
      }
      state = state.copyWith(
        installingIds: result.installed
            ? _installingIdsWithout(item.id)
            : state.installingIds,
        installedIds: installedIds,
        skillHubInstalledSlugs: skillHubInstalledSlugs,
        pendingInstallIds: pendingInstallIds,
        installMessages: {...state.installMessages, item.id: result.message},
        installStatuses: {...state.installStatuses, item.id: result.status},
        fallbackGateways: const [],
      );
      if (result.installed) {
        _refreshSkillCachesAfterChange();
      }
      return true;
    } catch (e) {
      if (e is SkillHubApiException &&
          e.actionError == 'fallback_gateway_required') {
        state = state.copyWith(
          installingIds: _installingIdsWithout(item.id),
          fallbackGateways: e.fallbackGateways,
          clearError: true,
        );
        return false;
      }
      state = state.copyWith(
        installingIds: _installingIdsWithout(item.id),
        fallbackGateways: const [],
        errorMessage: _errorMessage(e),
      );
      return false;
    }
  }

  void clearError() {
    if (state.errorMessage == null) return;
    state = state.copyWith(clearError: true);
  }

  void handleInstallStatus(Map<String, dynamic> payload) {
    final installId = _stringValue(payload['installId']).isEmpty
        ? _stringValue(payload['install_id'])
        : _stringValue(payload['installId']);
    final status = _stringValue(payload['status']);
    final slug = _normalizeSkillHubSlug(_stringValue(payload['slug']));
    final itemId = _itemIdForInstallStatus(installId, payload);
    if (itemId.isEmpty && slug.isEmpty) return;

    final nextInstalledSlugs = {...state.skillHubInstalledSlugs};
    final nextInstallPaths = {...state.skillHubInstallPaths};
    if (status == 'installed' && slug.isNotEmpty) {
      nextInstalledSlugs.add(slug);
      final path = _stringValue(payload['path']).isEmpty
          ? _stringValue(payload['skillPath'])
          : _stringValue(payload['path']);
      if (path.isNotEmpty) nextInstallPaths[slug] = path;
    }
    if (itemId.isEmpty) {
      state = state.copyWith(
        skillHubInstalledSlugs: nextInstalledSlugs,
        skillHubInstallPaths: nextInstallPaths,
      );
      if (status == 'installed') {
        _refreshSkillCachesAfterChange();
      }
      return;
    }

    final pendingInstallIds = {...state.pendingInstallIds}..remove(installId);
    final installMessages = {
      ...state.installMessages,
      itemId: _stringValue(payload['message']).isEmpty
          ? _messageForStatus(status)
          : _stringValue(payload['message']),
    };
    final installStatuses = {...state.installStatuses, itemId: status};

    if (status == 'installed') {
      state = state.copyWith(
        installingIds: _installingIdsWithout(itemId),
        installedIds: {...state.installedIds, itemId},
        skillHubInstalledSlugs: nextInstalledSlugs,
        skillHubInstallPaths: nextInstallPaths,
        pendingInstallIds: pendingInstallIds,
        installMessages: installMessages,
        installStatuses: installStatuses,
        clearError: true,
      );
      _refreshSkillCachesAfterChange();
      return;
    }

    if (status == 'failed') {
      state = state.copyWith(
        installingIds: _installingIdsWithout(itemId),
        pendingInstallIds: pendingInstallIds,
        installMessages: installMessages,
        installStatuses: installStatuses,
        errorMessage: installMessages[itemId],
      );
      return;
    }

    state = state.copyWith(
      pendingInstallIds: installId.isEmpty
          ? state.pendingInstallIds
          : {...state.pendingInstallIds, installId: itemId},
      skillHubInstalledSlugs: nextInstalledSlugs,
      skillHubInstallPaths: nextInstallPaths,
      installMessages: installMessages,
      installStatuses: installStatuses,
    );
  }

  String _errorMessage(Object error) {
    if (error is SkillHubApiException) {
      return switch (error.actionError) {
        'receive_timeout' => skillHubReceiveTimeoutUiCode,
        'network_error' => skillHubNetworkErrorUiCode,
        _ => error.message,
      };
    }
    return error.toString();
  }

  Set<String> _installingIdsWithout(String id) {
    return {...state.installingIds}..remove(id);
  }

  void _refreshSkillCachesAfterChange() {
    final ref = _ref;
    if (ref == null) return;
    unawaited(refreshSkillCaches(ref));
  }

  String _itemIdForInstallStatus(
    String installId,
    Map<String, dynamic> payload,
  ) {
    final pendingId = state.pendingInstallIds[installId];
    if (pendingId != null) return pendingId;
    final slug = _stringValue(payload['slug']);
    if (slug.isEmpty) return '';
    for (final item in state.items) {
      if (item.slug == slug) return item.id;
    }
    final selected = state.selected;
    if (selected != null && selected.slug == slug) return selected.id;
    return '';
  }

  String _messageForStatus(String status) {
    if (status == 'accepted') return '安装任务已提交';
    if (status == 'resolving') return '正在解析';
    if (status == 'downloading') return '正在下载';
    if (status == 'verifying') return '正在校验安装包';
    if (status == 'extracting') return '正在解压安装包';
    if (status == 'installing') return '正在安装 Skill';
    if (status == 'recording') return '正在记录安装信息';
    if (status == 'refreshing') return '正在刷新Skill缓存';
    if (status == 'fallback_pending') return '正在切换到 Gateway 原生安装';
    if (status == 'gateway_installing') return 'Gateway 原生安装中';
    if (status == 'installed') return '安装完成';
    if (status == 'failed') return '安装失败';
    return '正在安装';
  }
}

String _stringValue(Object? value) {
  return value?.toString() ?? '';
}

String _normalizeSkillHubSlug(String value) {
  return value.trim().toLowerCase();
}

bool _canRefreshSkillCache(GatewayInfo gateway) {
  if (gateway.status != GatewayConnectionStatus.online) return false;
  if (!gateway.supports('skills')) return false;
  return true;
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
