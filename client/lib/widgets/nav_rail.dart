import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client/screens/settings_screen.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/nav_page_provider.dart';
import 'package:client/core/env_config.dart';
import 'package:client/l10n/l10n.dart';

/// NavRail 宽度持久化 key
const _kNavRailWidthKey = 'clawke_nav_rail_width';
const _kDefaultNavWidth = 100.0;
const _kMinNavWidth = 60.0;
const _kMaxNavWidth = 200.0;
const _kExpandThreshold = 100.0;

class NavRail extends ConsumerStatefulWidget {
  const NavRail({super.key});

  @override
  ConsumerState<NavRail> createState() => _NavRailState();
}

class _NavRailState extends ConsumerState<NavRail> {
  double _width = _kDefaultNavWidth;

  @override
  void initState() {
    super.initState();
    _loadWidth();
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_kNavRailWidthKey);
    if (saved != null && mounted) {
      setState(() => _width = saved.clamp(_kMinNavWidth, _kMaxNavWidth));
    }
  }

  Future<void> _saveWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kNavRailWidthKey, _width);
  }

  bool get _isExpanded => _width >= _kExpandThreshold;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activePage = ref.watch(activeNavPageProvider);
    final user = ref.watch(authUserProvider);

    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Stack(
        children: [
          // 导航内容 — 占满整个区域
          Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Tooltip(
                  message: user?.loginId ?? user?.name ?? '',
                  waitDuration: const Duration(milliseconds: 300),
                  child: _buildTopAvatar(user, colorScheme),
                ),
              ),
              const SizedBox(height: 16),
              _NavItem(
                icon: Icons.chat_bubble,
                label: context.l10n.navChat,
                isActive: activePage == NavPage.chat,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  ref.read(activeNavPageProvider.notifier).state = NavPage.chat;
                },
              ),
              const SizedBox(height: 2),
              _NavItem(
                icon: Icons.dashboard,
                label: context.l10n.navDashboard,
                isActive: activePage == NavPage.dashboard,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  ref.read(activeNavPageProvider.notifier).state =
                      NavPage.dashboard;
                  ref.read(wsMessageHandlerProvider).requestDashboard();
                },
              ),
              const SizedBox(height: 2),
              _NavItem(
                icon: Icons.task_alt,
                label: _localized(context, 'Tasks', '任务管理'),
                isActive: activePage == NavPage.tasks,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  ref.read(activeNavPageProvider.notifier).state =
                      NavPage.tasks;
                },
              ),
              const SizedBox(height: 2),
              _NavItem(
                icon: Icons.extension,
                label: context.l10n.navSkills,
                isActive: activePage == NavPage.skills,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  ref.read(activeNavPageProvider.notifier).state =
                      NavPage.skills;
                },
              ),
              // MVP: Cron and Channels nav items hidden
              // TODO: Uncomment when these features are ready
              const Spacer(),
              _NavItem(
                icon: Icons.settings,
                label: context.l10n.settings,
                isActive: false,
                isExpanded: _isExpanded,
                colorScheme: colorScheme,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
          // 拖拽手柄 — 叠加在右侧，不影响导航内容布局
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
                    _width = (_width + details.delta.dx).clamp(
                      _kMinNavWidth,
                      _kMaxNavWidth,
                    );
                  });
                },
                onHorizontalDragEnd: (_) => _saveWidth(),
                child: const SizedBox(width: 5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部头像/Logo 区域：登录后显示用户头像，未登录显示 App Logo。
  Widget _buildTopAvatar(dynamic user, ColorScheme colorScheme) {
    if (user == null) {
      // 未登录：显示 App Logo
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          'assets/images/logo.png',
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
    }

    // 已登录：显示用户头像
    final photo = user.photo as String?;
    final hasPhoto = photo != null && photo.isNotEmpty;

    if (hasPhoto) {
      // 处理头像 URL：相对路径需拼接 webBaseUrl
      final photoUrl = photo.startsWith('http')
          ? photo
          : '${EnvConfig.webBaseUrl}$photo';
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          photoUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackAvatar(user, colorScheme),
        ),
      );
    }

    return _buildFallbackAvatar(user, colorScheme);
  }

  /// 无头像时的降级显示：名字首字母圆形头像。
  Widget _buildFallbackAvatar(dynamic user, ColorScheme colorScheme) {
    final name = user.name as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }
}

String _localized(BuildContext context, String en, String zh) {
  return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isExpanded;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isExpanded,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isExpanded ? '' : label,
      waitDuration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isActive
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              padding: EdgeInsets.symmetric(horizontal: isExpanded ? 10 : 0),
              child: Row(
                mainAxisAlignment: isExpanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    size: 24,
                  ),
                  if (isExpanded) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: isExpanded ? 1.0 : 0.0,
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Theme.of(
                              context,
                            ).textTheme.labelSmall!.fontSize,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
