import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/screens/conversation_list_screen.dart';
import 'package:client/screens/chat_screen.dart';
import 'package:client/screens/profile_screen.dart';
import 'package:client/screens/skills_management_screen.dart';
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
import 'package:client/services/auth_service.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/core/notification_service.dart';

/// Sidebar 宽度持久化 key
const _kSidebarWidthKey = 'clawke_sidebar_width';
const _kDefaultSidebarWidth = 280.0;
const _kMinSidebarWidth = 180.0;
const _kMaxSidebarWidth = 500.0;

/// 响应式断点：小于此宽度使用移动端布局
const _kMobileBreakpoint = 600.0;

class MainLayout extends ConsumerStatefulWidget {
  const MainLayout({super.key});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
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

  @override
  void initState() {
    super.initState();
    debugPrint('[MainLayout] 🏗️ initState called');
    _loadSidebarWidth();
    // App 启动：先等 host 加载完成，再建立 WebSocket 连接
    _initConnectionAsync();
    // 延迟请求通知权限：等首帧渲染完后再弹权限对话框，
    // 避免 macOS 启动时黑屏（权限弹窗阻塞 Flutter 引擎初始化）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.requestPermissions();
    });
    // 启动后 8 秒宽限期：给网络足够时间建立连接，
    // 避免审核员看到一闪而过的连接错误
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _inGracePeriod = false);
    });
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

    return Stack(
      children: [content, _buildFloatingAlert(context, ref, ws, aiState)],
    );
  }

  /// 构建浮动的底部错误提示
  Widget _buildFloatingAlert(
    BuildContext context,
    WidgetRef ref,
    WsState ws,
    AiBackendState aiState,
  ) {
    // 健康状态：ws 已连接且 AI 已连接
    final isHealthy =
        ws == WsState.connected && aiState == AiBackendState.connected;

    // 显示条件：已尝试过连接、不在宽限期、不健康、且未被用户关闭
    final showAlert =
        _hasEverAttempted && !_inGracePeriod && !_alertDismissed && !isHealthy;

    if (!showAlert) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isConnecting = ws == WsState.connecting;

    // 不暴露原始错误细节给用户（审核员不应看到技术错误信息）
    final alertText = switch (ws) {
      WsState.disconnected => context.l10n.serverDisconnected,
      WsState.connecting => context.l10n.connecting,
      WsState.connected when aiState == AiBackendState.disconnected =>
        context.l10n.aiBackendDisconnected,
      _ => '',
    };

    // 底部偏移：移动端需要避开 BottomNavigationBar
    final bottomOffset = _isMobile(context) ? 64.0 : 16.0;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomOffset,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: isConnecting
            ? colorScheme.secondaryContainer
            : colorScheme.error,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isConnecting
              ? null
              : () => ref.read(wsServiceProvider).reconnect(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                if (isConnecting)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  )
                else
                  Icon(
                    Icons.error_outline,
                    size: 20,
                    color: colorScheme.onError,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        alertText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isConnecting
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onError,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (ws == WsState.disconnected)
                        Text(
                          context.l10n.checkServerSetup,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onError.withValues(
                                  alpha: 0.8,
                                ),
                                decoration: TextDecoration.underline,
                                decorationColor: colorScheme.onError.withValues(
                                  alpha: 0.8,
                                ),
                              ),
                        ),
                    ],
                  ),
                ),
                // 重试按钮（连接中时不显示）
                if (!isConnecting)
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      size: 18,
                      color: colorScheme.onError,
                    ),
                    tooltip: context.l10n.connecting,
                    onPressed: () => ref.read(wsServiceProvider).reconnect(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                if (!isConnecting) const SizedBox(width: 4),
                // 关闭按钮
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: isConnecting
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onError,
                  ),
                  tooltip: context.l10n.cancel,
                  onPressed: () => setState(() => _alertDismissed = true),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  移动端布局
  // ─────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final sduiCache = ref.watch(sduiPageCacheProvider);
    final debugLogEnabled = ref.watch(debugLogEnabledProvider);

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
                  _buildMobileConversationList(context),
                  // 1: 仪表盘
                  _buildMobileDashboard(context, sduiCache, colorScheme),
                  // 2: 技能中心
                  const SkillsManagementScreen(showAppBar: true),
                  // 3: 我的
                  const ProfileScreen(),
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
          // 切到仪表盘时请求 SDUI 数据
          if (index == 1) {
            ref.read(wsMessageHandlerProvider).requestDashboard();
          }
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
            icon: const Icon(Icons.chat_bubble_outline),
            activeIcon: const Icon(Icons.chat_bubble),
            label: l10n.navChat,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: l10n.navDashboard,
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

  /// 移动端仪表盘：AppBar + SDUI 内容
  Widget _buildMobileDashboard(
    BuildContext context,
    Map<NavPage, dynamic> sduiCache,
    ColorScheme colorScheme,
  ) {
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.navDashboard),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildSduiPage(NavPage.dashboard, sduiCache, colorScheme),
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
              ref.read(selectedConversationIdProvider.notifier).state = convId;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(key: ValueKey(convId)),
                ),
              );
            },
          ),
        ],
      ),
      body: ConversationListScreen(
        showHeader: false,
        onConversationTap: (accountId) {
          // 移动端：push 全屏聊天页
          ref.read(selectedConversationIdProvider.notifier).state = accountId;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(key: ValueKey(accountId)),
            ),
          );
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
                      Row(
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
                                              (_sidebarWidth + details.delta.dx)
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
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                      // 1: 仪表盘
                      _buildSduiPage(NavPage.dashboard, sduiCache, colorScheme),
                      // 2: 定时任务
                      _buildSduiPage(NavPage.cron, sduiCache, colorScheme),
                      // 3: 频道管理
                      _buildSduiPage(NavPage.channels, sduiCache, colorScheme),
                      // 4: 技能中心
                      const SkillsManagementScreen(),
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
    ColorScheme colorScheme,
  ) {
    final sduiMessage = cache[page];
    if (sduiMessage == null) {
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
