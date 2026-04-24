import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/screens/settings_screen.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/l10n/l10n.dart';

/// 版本号常量（与 pubspec.yaml 同步，每次发布递增）
const _appVersion = '1.1.10';

/// 「我的」页面 — 移动端 Profile 入口
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = ref.watch(authUserProvider);

    final name = user?.name ?? 'Clawke User';
    final loginId = user?.loginId ?? '';
    final displaySub = loginId.isNotEmpty ? loginId : (user?.uid ?? '');
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.profile),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          // 头像 + 用户名
          Center(
            child: Column(
              children: [
                // 渐变圆环头像
                Container(
                  width: 80,
                  height: 80,
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
                      border:
                          Border.all(color: colorScheme.surface, width: 3),
                    ),
                    child: _buildAvatarContent(
                        user?.photo, initial, colorScheme),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
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
          ),
          const SizedBox(height: 32),
          // 设置入口
          _buildMenuItem(
            context,
            icon: Icons.settings_outlined,
            title: context.l10n.settings,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
          _buildMenuItem(
            context,
            icon: Icons.info_outline,
            title: context.l10n.about,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Clawke',
              applicationVersion: _appVersion,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent(
      String? photo, String initial, ColorScheme colorScheme) {
    if (photo != null && photo.isNotEmpty) {
      final photoUrl = MediaResolver.resolve(photo);
      return ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _buildInitialAvatar(initial, colorScheme),
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
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colorScheme.onSurfaceVariant),
      title: Text(title),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
