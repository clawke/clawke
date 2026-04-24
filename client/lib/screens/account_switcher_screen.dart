import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/account_summary.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/core/ws_service.dart';
import 'package:client/providers/auth_provider.dart';
import 'package:client/providers/conversation_provider.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/screens/welcome_screen.dart';
import 'package:client/main.dart';
import 'package:client/l10n/l10n.dart';

/// 切换账号页面 — 展示历史登录账号列表 + 添加账号入口。
class AccountSwitcherScreen extends ConsumerStatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  ConsumerState<AccountSwitcherScreen> createState() =>
      _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends ConsumerState<AccountSwitcherScreen> {
  List<AccountSummary> _accounts = [];
  bool _loading = true;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await AuthService.getKnownAccounts();
    if (mounted) {
      final currentUid = ref.read(authUserProvider)?.uid;
      // 当前账号永远排最前面
      accounts.sort((a, b) {
        if (a.uid == currentUid) return -1;
        if (b.uid == currentUid) return 1;
        return 0;
      });
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    }
  }

  Future<void> _switchTo(AccountSummary account) async {
    final t = context.l10n;
    setState(() => _switching = true);
    try {
      final user = await AuthService.switchToAccount(account);
      if (!mounted) return;

      // 清空当前选中会话（避免新用户看到旧用户的选中态）
      ref.read(selectedConversationIdProvider.notifier).state = null;
      // 更新用户 → 触发 DB 切换（currentUserUidProvider 级联重建）
      ref.read(authUserProvider.notifier).state = user;

      // ── 关键：切换 Relay 凭证 + Server 地址（与 LoginScreen._doLogin 对齐） ──
      debugPrint('[AccountSwitch] Fetching relay credentials for ${user.uid}...');
      final relay = await AuthService.fetchRelayCredentials();
      debugPrint('[AccountSwitch] Relay: ${relay.relayUrl}, token=${relay.token.substring(0, 4)}...');
      ref.read(relayCredentialsProvider.notifier).state = relay;

      // 更新 serverConfig（持久化到 SharedPreferences）
      await ref.read(serverConfigProvider.notifier).ensureLoaded();
      await ref.read(serverConfigProvider.notifier).setServerAddress(relay.relayUrl);
      await ref.read(serverConfigProvider.notifier).setToken(relay.token);

      // 同步更新 WsService / MediaResolver 的 static 状态
      final updatedConfig = ref.read(serverConfigProvider);
      WsService.setUrl(updatedConfig.wsUrl);
      WsService.setToken(updatedConfig.token);
      MediaResolver.setBaseUrl(updatedConfig.httpUrl);
      MediaResolver.setToken(updatedConfig.token);
      debugPrint('[AccountSwitch] Server config updated: ws=${updatedConfig.wsUrl}');

      if (!mounted) return;

      // 导航到 AuthGate → MainLayout 重建
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.accountExpired)),
      );
      // 刷新列表（过期账号已被移除）
      _loadAccounts();
    }
  }

  Future<void> _removeAccount(AccountSummary account) async {
    await AuthService.removeKnownAccount(account.uid);
    _loadAccounts();
  }

  void _addAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WelcomeScreen(showBackButton: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = context.l10n;
    final currentUid = ref.watch(authUserProvider)?.uid;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(t.switchAccount),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    // 账号列表
                    if (_accounts.isNotEmpty) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: List.generate(_accounts.length, (i) {
                            final account = _accounts[i];
                            final isCurrent = account.uid == currentUid;
                            final isLast = i == _accounts.length - 1;
                            return _AccountTile(
                              account: account,
                              isCurrent: isCurrent,
                              isLast: isLast,
                              currentLabel: t.currentAccount,
                              onTap: isCurrent
                                  ? null
                                  : () => _switchTo(account),
                              onDismissed: isCurrent
                                  ? null
                                  : () => _removeAccount(account),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          t.switchAccountHint,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // 添加账号
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _addAccount,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.add,
                                  color: colorScheme.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                t.addAccount,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w500,
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

                // 切换中遮罩
                if (_switching)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
//  账号行
// ─────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final AccountSummary account;
  final bool isCurrent;
  final bool isLast;
  final String currentLabel;
  final VoidCallback? onTap;
  final VoidCallback? onDismissed;

  const _AccountTile({
    required this.account,
    required this.isCurrent,
    required this.isLast,
    required this.currentLabel,
    this.onTap,
    this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = account.name.isNotEmpty
        ? account.name.characters.first.toUpperCase()
        : '?';
    final displaySub = account.loginId ?? account.uid;

    Widget tile = Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // 头像
                _buildAvatar(initial, colorScheme),
                const SizedBox(width: 14),

                // 名称 + loginId
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displaySub,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 当前标记 or 箭头
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      currentLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 70,
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
      ],
    );

    // 非当前账号支持左滑删除
    if (onDismissed != null) {
      tile = Dismissible(
        key: ValueKey(account.uid),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: colorScheme.error,
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        onDismissed: (_) => onDismissed!(),
        child: tile,
      );
    }

    return tile;
  }

  Widget _buildAvatar(String initial, ColorScheme colorScheme) {
    if (account.photo != null && account.photo!.isNotEmpty) {
      final url = MediaResolver.resolve(account.photo!);
      return Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isCurrent
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
        ),
        child: ClipOval(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: 42,
            height: 42,
            errorBuilder: (_, __, ___) =>
                _buildInitialAvatar(initial, colorScheme),
          ),
        ),
      );
    }
    return _buildInitialAvatar(initial, colorScheme);
  }

  Widget _buildInitialAvatar(String initial, ColorScheme colorScheme) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent
            ? colorScheme.primary.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHigh,
        border: isCurrent
            ? Border.all(color: colorScheme.primary, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isCurrent
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
