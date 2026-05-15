import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/screens/conversation_list_screen.dart';
import 'package:client/screens/chat_screen.dart';
import 'package:client/screens/dashboard_management_screen.dart';
import 'package:client/screens/profile_screen.dart';
import 'package:client/screens/skills_management_screen.dart';
import 'package:client/screens/tasks_management_screen.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/providers/debug_log_provider.dart';
import 'package:client/providers/nav_page_provider.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/widgets/nav_rail.dart';
import 'package:client/widgets/debug_log_panel.dart';
import 'package:client/widgets/widget_factory.dart';
import 'package:client/widgets/app_floating_notice.dart';
import 'package:client/widgets/unread_count_badge.dart';
import 'package:client/widgets/notification_permission_dialog.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/core/notification_click_router.dart';
import 'package:client/core/notification_event.dart';
import 'package:client/core/notification_service.dart';
import 'package:client/core/push_registration_service.dart';

/// Sidebar 宽度持久化 key
const _kSidebarWidthKey = 'clawke_sidebar_width';
const _kDefaultSidebarWidth = 280.0;
const _kMinSidebarWidth = 180.0;
const _kMaxSidebarWidth = 500.0;
const _kNotificationIntroSeenKey = 'clawke_notification_intro_seen';
const _kNotificationUserRequestedKey = 'clawke_notification_user_requested';
const _isUiE2eRun = String.fromEnvironment('CLAWKE_E2E_RUN_DIR') != '';

/// 响应式断点：小于此宽度使用移动端布局
const _kMobileBreakpoint = 600.0;

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

Widget buildLazyIndexedChild({required bool isActive, required Widget child}) {
  return buildIndexedChild(
    isActive: isActive,
    child: isActive ? child : const SizedBox.shrink(),
  );
}

Widget buildIndexedChild({required bool isActive, required Widget child}) {
  return TickerMode(enabled: isActive, child: child);
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  double _sidebarWidth = _kDefaultSidebarWidth;

  /// 移动端底部导航栏当前选中索引
  int _mobileTabIndex = 0;

  /// 用户是否手动关闭了错误提示
  bool _alertDismissed = false;

  /// 是否已经尝试过连接（避免初始化时就显示错误提示）
  bool _hasEverAttempted = false;

  /// 首次连接的宽限期（避免启动后立即弹错误）
  bool _inGracePeriod = true;

  /// 连接是否曾成功过（只有曾成功再断开才重置 dismissed）
  bool _hasEverConnected = false;

  bool _notificationPermissionPromptOpen = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[MainLayout] 🏗️ initState called');
    _loadSidebarWidth();
    unawaited(
      PushRegistrationService.configureRemotePushHandling((payload) {
        final handler = ref.read(wsMessageHandlerProvider);
        handler.requestSyncFromRemotePush();
        final tapPayload = payload.toNotificationTapPayload();
        if (tapPayload != null) {
          _scheduleNotificationPayload(tapPayload);
        }
      }),
    );
    NotificationService.setTapHandler((payload) {
      final router = ref.read(notificationClickRouterProvider);
      if (!mounted) {
        router.savePending(payload);
        return;
      }
      _scheduleNotificationPayload(payload);
    });
    // App 启动：先等 host 加载完成，再建立 WebSocket 连接
    _initConnectionAsync();
    // 延迟请求通知权限：等首帧渲染完后再弹权限对话框，
    // 避免 macOS 启动时黑屏（权限弹窗阻塞 Flutter 引擎初始化）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushPendingNotificationPayload();
      _maybeShowNotificationPermissionPrompt();
      NotificationService.setApplicationBadgeCount(
        ref.read(systemBadgeCountProvider),
      );
    });
    // 启动后 8 秒宽限期：给网络足够时间建立连接，
    // 避免审核员看到一闪而过的连接错误
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _inGracePeriod = false);
    });
  }

  @override
  void dispose() {
    NotificationService.setTapHandler(null);
    super.dispose();
  }

  bool _openNotificationPayload(NotificationPayload payload) {
    if (!mounted || payload.conversationId.trim().isEmpty) return false;

    final convId = payload.conversationId;
    final conversations = ref.read(conversationListProvider).valueOrNull;
    if (conversations == null ||
        !conversations.any((item) => item.conversationId == convId)) {
      debugPrint('[NotificationClick] waiting for conversation: $convId');
      return false;
    }

    final alreadyVisible =
        ref.read(selectedConversationIdProvider) == convId &&
        ref.read(activeChatConversationIdProvider) == convId &&
        ref.read(activeNavPageProvider) == NavPage.chat;

    debugPrint('[NotificationClick] opening conversation: $convId');
    ref.read(activeNavPageProvider.notifier).state = NavPage.chat;
    ref.read(selectedConversationIdProvider.notifier).state = convId;

    if (!_isMobile(context)) return true;
    if (alreadyVisible) return true;

    setState(() => _mobileTabIndex = 0);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(key: ValueKey(convId))),
    );
    return true;
  }

  void _scheduleNotificationPayload(NotificationPayload payload) {
    final router = ref.read(notificationClickRouterProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        router.savePending(payload);
        return;
      }
      router.handleTap(payload, _openNotificationPayload);
    });
  }

  void _flushPendingNotificationPayload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(notificationClickRouterProvider)
          .flushPending(_openNotificationPayload);
    });
  }

  void _openMobileConversation(BuildContext context, String convId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.mounted) return;
      ref.read(selectedConversationIdProvider.notifier).state = convId;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(key: ValueKey(convId))),
      );
    });
  }

  Future<void> _maybeShowNotificationPermissionPrompt() async {
    if (_notificationPermissionPromptOpen || !mounted) return;
    if (_isUiE2eRun) return;

    _notificationPermissionPromptOpen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final permissions =
          await NotificationService.checkNotificationPermissions();
      if (!mounted || permissions == null) return;
      if (permissions.canShowSystemNotifications) {
        debugPrint('[PushRegistration] notification permission enabled');
        _registerPushDevice();
        return;
      }
      debugPrint('[PushRegistration] notification permission not enabled');

      final introSeen = prefs.getBool(_kNotificationIntroSeenKey) ?? false;
      final userRequested =
          prefs.getBool(_kNotificationUserRequestedKey) ?? false;

      if (!introSeen) {
        final shouldEnable =
            await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => const NotificationPermissionIntroDialog(),
            ) ??
            false;
        await prefs.setBool(_kNotificationIntroSeenKey, true);
        if (!shouldEnable || !mounted) return;

        await prefs.setBool(_kNotificationUserRequestedKey, true);
        final updated = await NotificationService.requestPermissions();
        if (!mounted) return;
        if (updated?.canShowSystemNotifications == true) {
          debugPrint('[PushRegistration] notification permission granted');
          _registerPushDevice();
          return;
        }
        debugPrint('[PushRegistration] notification permission denied');

        await _showNotificationSettingsGuideDialog();
        return;
      }

      if (userRequested) {
        await _showNotificationSettingsGuideDialog();
      }
    } finally {
      _notificationPermissionPromptOpen = false;
    }
  }

  void _registerPushDevice() {
    unawaited(PushRegistrationService.registerCurrentDeviceWithServer());
  }

  Future<void> _showNotificationSettingsGuideDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => const NotificationPermissionSettingsGuideDialog(
        onOpenSettings: NotificationService.openNotificationSettings,
      ),
    );
  }

  Future<void> _initConnectionAsync() async {
    try {
      // 等待 ServerConfigNotifier 从 SharedPreferences 加载完成
      await ref.read(serverConfigProvider.notifier).ensureLoaded();
      // 使用当前最新 state（可能被 ManualConfigScreen 或 LoginScreen 更新过）
      final config = ref.read(serverConfigProvider);
      WsService.setUrl(config.wsUrl);
      WsService.setToken(config.token);
      MediaResolver.setBaseUrl(config.httpUrl);
      MediaResolver.setToken(config.token);
      final permissions =
          await NotificationService.checkNotificationPermissions();
      if (permissions?.canShowSystemNotifications == true) {
        _registerPushDevice();
      }
      // 先初始化消息处理器（确保 stream 订阅在连接之前就绑定好）
      ref.read(wsMessageHandlerProvider);

      // 发起连接
      ref.read(wsServiceProvider).connect();
    } catch (e, st) {
      debugPrint('[MainLayout] ❌ _initConnectionAsync error: $e\n$st');
    }
  }

  void _showAuthFailedDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.connectionAuthFailed),
        content: Text(context.l10n.relayConnectionRefused),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.later),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              // 清除认证状态，返回欢迎页
              await AuthService.logout();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('clawke_http_url');
              await prefs.remove('clawke_ws_url');
              await prefs.remove('clawke_token');
              ref.read(authFailedProvider.notifier).state = false;
              if (mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
            child: Text(context.l10n.reLogin),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kSidebarWidthKey);
    if (saved != null && mounted) {
      setState(
        () => _sidebarWidth = saved.clamp(_kMinSidebarWidth, _kMaxSidebarWidth),
      );
    }
  }

  Future<void> _saveSidebarWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSidebarWidthKey, _sidebarWidth);
  }

  /// 判断是否为移动端布局
  bool _isMobile(BuildContext context) {
    if (Platform.isIOS || Platform.isAndroid) return true;
    return MediaQuery.of(context).size.width < _kMobileBreakpoint;
  }

  @override
  Widget build(BuildContext context) {
    // 监听认证失败 → 弹窗提示重新登录（必须在 build 中调用，不能在 async 函数中）
    ref.listen<bool>(authFailedProvider, (prev, next) {
      if (next && mounted) {
        _showAuthFailedDialog();
      }
    });
    ref.listen<int>(systemBadgeCountProvider, (prev, next) {
      NotificationService.setApplicationBadgeCount(next);
    });
    ref.listen(conversationListProvider, (prev, next) {
      if (!next.hasValue) return;
      _flushPendingNotificationPayload();
    });

    // 监听连接状态变化（watch 仍触发 rebuild，但取同步值避免 AsyncValue 过渡态闪烁）
    ref.watch(wsStateProvider);
    final aiState = ref.watch(aiBackendStateProvider);
    final wsService = ref.watch(wsServiceProvider);
    final ws = wsService.state;

    // 首次进入 connecting 以上状态时，标记已尝试连接
    if (!_hasEverAttempted && ws != WsState.disconnected) {
      _hasEverAttempted = true;
    }
    // 如果曾经连接过又断开了，也标记
    if (!_hasEverAttempted &&
        ws == WsState.disconnected &&
        wsService.lastError != null) {
      _hasEverAttempted = true;
    }

    final isHealthy =
        ws == WsState.connected && aiState == AiBackendState.connected;

    // 标记曾经成功连接过
    if (isHealthy && !_hasEverConnected) {
      _hasEverConnected = true;
    }

    // 只有曾成功连接后再断开时，才重置 dismissed 状态
    // （避免审核员首次使用时反复弹错误提示）
    if (isHealthy && _alertDismissed && _hasEverConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _alertDismissed = false);
      });
    }

    final content = _isMobile(context)
        ? _buildMobileLayout(context)
        : _buildDesktopLayout(context);

    return Stack(children: [content, _buildFloatingAlert(context, ref, ws)]);
  }

  /// 构建浮动的底部错误提示
  Widget _buildFloatingAlert(BuildContext context, WidgetRef ref, WsState ws) {
    // 显示条件：已尝试过连接、不在宽限期、WS 未连接、且未被用户关闭
    final showAlert =
        _hasEverAttempted &&
        !_inGracePeriod &&
        !_alertDismissed &&
        ws != WsState.connected;

    if (!showAlert) return const SizedBox.shrink();

    final isConnecting = ws == WsState.connecting;

    // 不暴露原始错误细节给用户（审核员不应看到技术错误信息）
    final alertText = switch (ws) {
      WsState.disconnected => context.l10n.serverDisconnected,
      WsState.connecting => context.l10n.connecting,
      _ => '',
    };

    // 底部偏移：移动端需要避开 BottomNavigationBar
    final isMobileLayout = _isMobile(context);
    final bottomOffset = isMobileLayout ? 64.0 : 16.0;
    final horizontalInset = isMobileLayout ? 0.0 : 16.0;

    return isConnecting
        ? AppFloatingNotice.info(
            message: alertText,
            showProgress: true,
            edgeToEdge: isMobileLayout,
            bottom: bottomOffset,
            horizontalInset: horizontalInset,
            onDismiss: () => setState(() => _alertDismissed = true),
          )
        : AppFloatingNotice.error(
            message: alertText,
            detail: context.l10n.checkServerSetup,
            onAction: () => ref.read(wsServiceProvider).reconnect(),
            actionIcon: Icons.refresh,
            actionTooltip: context.l10n.connecting,
            edgeToEdge: isMobileLayout,
            bottom: bottomOffset,
            horizontalInset: horizontalInset,
            onDismiss: () => setState(() => _alertDismissed = true),
          );
  }

  // ─────────────────────────────────────────────
  //  移动端布局
  // ─────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final debugLogEnabled = ref.watch(debugLogEnabledProvider);
    final unreadCount = ref.watch(totalUnseenCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false, // 底部由 BottomNavigationBar 处理
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _mobileTabIndex,
                children: [
                  // 0: 会话列表（点击后 push 到聊天页）
                  buildIndexedChild(
                    isActive: _mobileTabIndex == 0,
                    child: _buildMobileConversationList(context),
                  ),
                  // 1: 仪表盘
                  buildIndexedChild(
                    isActive: _mobileTabIndex == 1,
                    child: const DashboardManagementScreen(showAppBar: true),
                  ),
                  // 2: 任务管理
                  buildLazyIndexedChild(
                    isActive: _mobileTabIndex == 2,
                    child: const TasksManagementScreen(showAppBar: true),
                  ),
                  // 3: 技能中心
                  buildLazyIndexedChild(
                    isActive: _mobileTabIndex == 3,
                    child: const SkillsManagementScreen(showAppBar: true),
                  ),
                  // 4: 我的
                  buildLazyIndexedChild(
                    isActive: _mobileTabIndex == 4,
                    child: const ProfileScreen(),
                  ),
                ],
              ),
            ),
            // 调试日志面板（移动端）
            if (debugLogEnabled) const DebugLogPanel(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _mobileTabIndex,
        onTap: (index) {
          setState(() => _mobileTabIndex = index);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: colorScheme.surface,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        iconSize: 22,
        items: [
          BottomNavigationBarItem(
            icon: UnreadBadgeIcon(
              icon: Icons.chat_bubble_outline,
              count: unreadCount,
              semanticsLabel: '${l10n.navChat}未读消息 $unreadCount',
              badgeKey: ValueKey(
                'ui_e2e_nav_unread_${l10n.navChat}_$unreadCount',
              ),
              iconColor: colorScheme.onSurfaceVariant,
              badgeBackgroundColor: colorScheme.error,
              badgeForegroundColor: colorScheme.onError,
              iconSize: 22,
            ),
            activeIcon: UnreadBadgeIcon(
              icon: Icons.chat_bubble,
              count: unreadCount,
              semanticsLabel: '${l10n.navChat}未读消息 $unreadCount',
              badgeKey: ValueKey(
                'ui_e2e_nav_unread_${l10n.navChat}_$unreadCount',
              ),
              iconColor: colorScheme.primary,
              badgeBackgroundColor: colorScheme.error,
              badgeForegroundColor: colorScheme.onError,
              iconSize: 22,
            ),
            label: l10n.navChat,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: l10n.navDashboard,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.task_alt_outlined),
            activeIcon: const Icon(Icons.task_alt),
            label: _localized(context, 'Tasks', '任务'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.extension_outlined),
            activeIcon: const Icon(Icons.extension),
            label: l10n.navSkills,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }

  /// 移动端会话列表：AppBar 只有标题，点击会话 push 到聊天页
  Widget _buildMobileConversationList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.navChat),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          NewConversationButton(
            iconSize: 26,
            onCreated: (convId) {
              _openMobileConversation(context, convId);
            },
          ),
        ],
      ),
      body: ConversationListScreen(
        showHeader: false,
        onConversationTap: (accountId) {
          _openMobileConversation(context, accountId);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  桌面端布局（保持不变）
  // ─────────────────────────────────────────────

  Widget _buildDesktopLayout(BuildContext context) {
    final selectedConvId = ref.watch(selectedConversationIdProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final debugLogEnabled = ref.watch(debugLogEnabledProvider);
    final activePage = ref.watch(activeNavPageProvider);
    final sduiCache = ref.watch(sduiPageCacheProvider);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // 左侧导航栏（含内部拖拽手柄）
                const NavRail(),
                // 右侧内容区 — IndexedStack 保留所有页面状态
                Expanded(
                  child: IndexedStack(
                    index: activePage.index,
                    children: [
                      // 0: 会话页（侧栏 + 聊天）
                      buildIndexedChild(
                        isActive: activePage == NavPage.chat,
                        child: Row(
                          children: [
                            // 可拖拽侧边栏（含内部拖拽手柄）
                            Container(
                              width: _sidebarWidth,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                border: Border(
                                  right: BorderSide(
                                    color: colorScheme.outlineVariant,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  const ConversationListScreen(),
                                  // 拖拽手柄 — 叠加在右侧
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.resizeColumn,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (details) {
                                          setState(() {
                                            _sidebarWidth =
                                                (_sidebarWidth +
                                                        details.delta.dx)
                                                    .clamp(
                                                      _kMinSidebarWidth,
                                                      _kMaxSidebarWidth,
                                                    );
                                          });
                                        },
                                        onHorizontalDragEnd: (_) =>
                                            _saveSidebarWidth(),
                                        child: const SizedBox(width: 5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: selectedConvId != null
                                  ? ChatScreen(key: ValueKey(selectedConvId))
                                  : Center(
                                      child: Text(
                                        context.l10n.selectConversationToStart,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      // 1: 仪表盘
                      buildLazyIndexedChild(
                        isActive: activePage == NavPage.dashboard,
                        child: const DashboardManagementScreen(),
                      ),
                      // 2: 任务管理
                      buildLazyIndexedChild(
                        isActive: activePage == NavPage.tasks,
                        child: const TasksManagementScreen(),
                      ),
                      // 3: 定时任务（旧 SDUI 页，导航暂隐藏）
                      buildIndexedChild(
                        isActive: activePage == NavPage.cron,
                        child: _buildSduiPage(
                          NavPage.cron,
                          sduiCache,
                          colorScheme,
                          isActive: activePage == NavPage.cron,
                        ),
                      ),
                      // 4: 频道管理
                      buildIndexedChild(
                        isActive: activePage == NavPage.channels,
                        child: _buildSduiPage(
                          NavPage.channels,
                          sduiCache,
                          colorScheme,
                          isActive: activePage == NavPage.channels,
                        ),
                      ),
                      // 5: 技能中心
                      buildLazyIndexedChild(
                        isActive: activePage == NavPage.skills,
                        child: const SkillsManagementScreen(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 调试日志面板
          if (debugLogEnabled) const DebugLogPanel(),
        ],
      ),
    );
  }

  /// 构建 SDUI 工具页面
  Widget _buildSduiPage(
    NavPage page,
    Map<NavPage, dynamic> cache,
    ColorScheme colorScheme, {
    required bool isActive,
  }) {
    final sduiMessage = cache[page];
    if (sduiMessage == null) {
      if (!isActive) {
        return const SizedBox.shrink();
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.loading,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Container(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(_isMobile(context) ? 8 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: WidgetFactory.build(
              sduiMessage.component,
              sduiMessage.messageId,
            ),
          ),
        ),
      ),
    );
  }
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}
