import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/core/url_utils.dart';
import 'package:client/screens/server_settings_page.dart';
import 'package:client/screens/appearance_settings_page.dart';
import 'package:client/screens/modify_password_screen.dart';
import 'package:client/main.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/screens/account_switcher_screen.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/theme_provider.dart';
import 'package:client/providers/locale_provider.dart';
import 'package:client/providers/debug_log_provider.dart';
import 'package:client/providers/chat_provider.dart';
import 'package:client/providers/mermaid_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/providers/font_scale_provider.dart';
import 'package:client/models/user_model.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/l10n/l10n.dart';

/// 设置主页 — 用户卡片 + 分组菜单布局。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final t = context.l10n;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(t.settings),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── 用户卡片 ──
          _ProfileCard(user: user),
          const SizedBox(height: 20),

          // ── 通用 ──
          _buildSectionTitle(context, t.general),
          _MenuCard(
            children: [
              _buildAppearanceRow(context, ref, colorScheme, t),
            ],
          ),
          const SizedBox(height: 20),

          // ── 安全 ──
          _buildSectionTitle(context, t.security),
          _MenuCard(
            children: [
              _MenuRow(
                icon: Icons.lock_outline,
                iconColor: const Color(0xFF7c6cf0),
                iconBg: const Color(0xFF7c6cf0).withValues(alpha: 0.12),
                label: t.modifyPassword,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ModifyPasswordScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 开发者 ──
          _buildSectionTitle(context, t.developer),
          _buildDeveloperSection(context, ref, colorScheme, t),
          const SizedBox(height: 20),

          // ── 法律 ──
          _buildSectionTitle(context, t.legal),
          _buildLegalSection(context, t),
          const SizedBox(height: 24),

          // ── 退出登录 ──
          _MenuCard(
            children: [
              _MenuRow(
                icon: Icons.swap_horiz,
                iconColor: const Color(0xFF60a5fa),
                iconBg: const Color(0xFF60a5fa).withValues(alpha: 0.12),
                label: t.switchAccount,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AccountSwitcherScreen()),
                ),
              ),
              _MenuRow(
                icon: Icons.logout,
                iconColor: colorScheme.error,
                iconBg: colorScheme.error.withValues(alpha: 0.1),
                label: t.logout,
                labelColor: colorScheme.error,
                showChevron: false,
                isLast: true,
                onTap: () => _handleLogout(context, ref),
              ),
              // 注销账户功能暂时隐藏
              // _MenuRow(
              //   icon: Icons.person_remove_outlined,
              //   iconColor: colorScheme.error,
              //   iconBg: colorScheme.error.withValues(alpha: 0.1),
              //   label: t.deleteAccount,
              //   labelColor: colorScheme.error,
              //   showChevron: false,
              //   isLast: true,
              //   onTap: () => _handleDeleteAccount(context, ref),
              // ),
            ],
          ),

          // ── 版本号 ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Clawke v1.0.38',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  /// 外观与主题 — 聚合显示当前状态，点击进入子页面。
  Widget _buildAppearanceRow(
      BuildContext context, WidgetRef ref, ColorScheme colorScheme, dynamic t) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final fontScale = ref.watch(fontScaleProvider);

    final currentLang =
        locale?.languageCode ?? Localizations.localeOf(context).languageCode;
    final langLabel = currentLang == 'zh' ? '中文' : 'English';

    String themeName;
    switch (themeMode) {
      case ThemeMode.light:
        themeName = t.lightMode;
      case ThemeMode.dark:
        themeName = t.darkMode;
      case ThemeMode.system:
        themeName = t.systemMode;
    }

    final fontPct = '${(fontScale * 100).round()}%';

    return _MenuRow(
      icon: Icons.palette_outlined,
      iconColor: const Color(0xFF60a5fa),
      iconBg: const Color(0xFF60a5fa).withValues(alpha: 0.12),
      label: t.appearanceAndLanguage,
      subtitle: '$themeName · $langLabel · ${t.fontSize} $fontPct',
      isLast: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppearanceSettingsPage()),
      ),
    );
  }

  /// 开发者区域。
  Widget _buildDeveloperSection(
      BuildContext context, WidgetRef ref, ColorScheme colorScheme, dynamic t) {
    final mermaidEnabled = ref.watch(mermaidEnabledProvider);
    final debugLogEnabled = ref.watch(debugLogEnabledProvider);
    final serverConfig = ref.watch(serverConfigProvider);

    return _MenuCard(
      children: [
        _MenuRow(
          icon: Icons.dns_outlined,
          iconColor: const Color(0xFF34d399),
          iconBg: const Color(0xFF34d399).withValues(alpha: 0.12),
          label: t.serverConnection,
          subtitle: serverConfig.httpUrl,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ServerSettingsPage()),
          ),
        ),
        _MenuRow(
          icon: Icons.auto_graph,
          iconColor: const Color(0xFFfb923c),
          iconBg: const Color(0xFFfb923c).withValues(alpha: 0.12),
          label: t.mermaidRender,
          subtitle: t.mermaidRenderSubtitle,
          trailing: Switch(
            value: mermaidEnabled,
            onChanged: (value) {
              ref.read(mermaidEnabledProvider.notifier).toggle(value);
            },
          ),
          showChevron: false,
          onTap: () {
            ref.read(mermaidEnabledProvider.notifier).toggle(!mermaidEnabled);
          },
        ),
        _MenuRow(
          icon: Icons.bug_report_outlined,
          iconColor: const Color(0xFFfb923c),
          iconBg: const Color(0xFFfb923c).withValues(alpha: 0.12),
          label: t.debugLog,
          subtitle: t.debugLogSubtitle,
          trailing: Switch(
            value: debugLogEnabled,
            onChanged: (value) {
              ref.read(debugLogEnabledProvider.notifier).setEnabled(value);
            },
          ),
          showChevron: false,
          onTap: () {
            ref
                .read(debugLogEnabledProvider.notifier)
                .setEnabled(!debugLogEnabled);
          },
        ),
        _MenuRow(
          icon: Icons.system_update_outlined,
          iconColor: const Color(0xFFfb923c),
          iconBg: const Color(0xFFfb923c).withValues(alpha: 0.12),
          label: t.checkUpdate,
          subtitle: t.currentVersion('1.0.36'),
          isLast: true,
          onTap: () {
            ref.read(wsMessageHandlerProvider).sendCheckUpdate();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t.checkingUpdate),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 法律信息。
  Widget _buildLegalSection(BuildContext context, dynamic t) {
    return _MenuCard(
      children: [
        _MenuRow(
          icon: Icons.article_outlined,
          iconColor: const Color(0xFF94a3b8),
          iconBg: const Color(0xFF94a3b8).withValues(alpha: 0.12),
          label: t.termsOfService,
          onTap: () => openTermsOfService(context),
        ),
        _MenuRow(
          icon: Icons.policy_outlined,
          iconColor: const Color(0xFF94a3b8),
          iconBg: const Color(0xFF94a3b8).withValues(alpha: 0.12),
          label: t.privacyPolicy,
          isLast: true,
          onTap: () => openPrivacyPolicy(context),
        ),
      ],
    );
  }

  /// 登出确认。
  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.logoutConfirmTitle),
        content: Text(t.logoutConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                Text(t.logout, style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await AuthService.logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      }
    }
  }

  /// 注销账户确认。
  Future<void> _handleDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteAccount),
        content: Text(t.deleteAccountConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(t.confirmDeleteAccount),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await AuthService.deleteAccount();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthGate()),
            (route) => false,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.deleteAccountFailed(e.toString()))),
          );
        }
      }
    }
  }
}

// ─────────────────────────────────────────────
//  用户卡片
// ─────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final UserVO? user;

  const _ProfileCard({this.user});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final name = user?.name ?? 'Clawke User';
    final loginId = user?.loginId ?? '';
    final displaySub = loginId.isNotEmpty ? loginId : (user?.uid ?? '');
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  colorScheme.surfaceContainerHigh,
                  colorScheme.surfaceContainerLow,
                ]
              : [
                  colorScheme.primaryContainer.withValues(alpha: 0.3),
                  colorScheme.surface,
                ],
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          // 头像 — 渐变圆环
          Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withValues(alpha: 0.6),
                  colorScheme.tertiary,
                ],
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surface,
                border: Border.all(color: colorScheme.surface, width: 3),
              ),
              child: _buildAvatarContent(initial, colorScheme),
            ),
          ),
          const SizedBox(height: 12),

          // 名称
          Text(
            name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),

          // LoginId or UID
          if (displaySub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              displaySub,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarContent(String initial, ColorScheme colorScheme) {
    if (user?.photo != null && user!.photo!.isNotEmpty) {
      final photoUrl = MediaResolver.resolve(user!.photo!);
      return ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildInitialAvatar(initial, colorScheme),
        ),
      );
    }
    return _buildInitialAvatar(initial, colorScheme);
  }

  Widget _buildInitialAvatar(String initial, ColorScheme colorScheme) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  菜单卡片容器
// ─────────────────────────────────────────────

class _MenuCard extends StatelessWidget {
  final List<Widget> children;

  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

// ─────────────────────────────────────────────
//  菜单行
// ─────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color? labelColor;
  final String? subtitle;
  final Widget? trailing;
  final bool showChevron;
  final bool isLast;
  final VoidCallback? onTap;

  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.labelColor,
    this.subtitle,
    this.trailing,
    this.showChevron = true,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 14),

                // Label + subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: labelColor ?? colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Trailing widget
                if (trailing != null) trailing!,

                // Chevron
                if (showChevron)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // Divider (除最后一项)
        if (!isLast)
          Divider(
            height: 1,
            indent: 62,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}
