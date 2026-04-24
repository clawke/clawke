import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/providers/ws_state_provider.dart';
import 'package:client/services/media_resolver.dart';
import 'package:client/core/ws_service.dart';
import 'package:http/http.dart' as http;
import 'package:client/l10n/l10n.dart';

/// 服务器连接子页面 — 地址 + Token 输入，统一保存 + 验证。
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  late TextEditingController _serverUrlController;
  late TextEditingController _tokenController;

  bool _saving = false;
  bool _obscureToken = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final config = ref.read(serverConfigProvider);
    _serverUrlController = TextEditingController(text: config.httpUrl);
    _tokenController = TextEditingController(text: config.token);
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 验证 URL 格式。
  String? _validateUrl(String url, BuildContext context) {
    final t = context.l10n;
    if (url.isEmpty) return t.serverAddressEmpty;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return t.serverAddressInvalidProtocol;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return t.serverAddressInvalidFormat;
    return null;
  }

  /// 验证服务器连通性。
  Future<bool> _checkConnectivity(String url) async {
    try {
      final healthUrl = url.endsWith('/') ? '${url}health' : '$url/health';
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 保存逻辑：验证 → 保存 → 重连。
  Future<void> _handleSave() async {
    final serverUrl = _serverUrlController.text.trim();
    final token = _tokenController.text.trim();

    // 1. 验证 URL 格式
    final urlError = _validateUrl(serverUrl, context);
    if (urlError != null) {
      setState(() => _errorMessage = urlError);
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    // 2. 验证连通性
    final reachable = await _checkConnectivity(serverUrl);
    if (!reachable) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = context.l10n.serverUnreachable;
        });
      }
      return;
    }

    // 3. 保存配置
    await ref.read(serverConfigProvider.notifier).setServerAddress(serverUrl);
    if (token.isNotEmpty) {
      await ref.read(serverConfigProvider.notifier).setToken(token);
    } else {
      await ref.read(serverConfigProvider.notifier).setToken('');
    }

    // 4. 更新运行时 & 重连
    final config = ref.read(serverConfigProvider);
    WsService.setUrl(config.wsUrl);
    WsService.setToken(config.token);
    MediaResolver.setBaseUrl(config.httpUrl);
    MediaResolver.setToken(config.token);
    ref.read(wsServiceProvider).reconnect();

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.saved),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.serverConnection),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 服务器地址
                    Text(
                      context.l10n.serverAddress,
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _serverUrlController,
                      decoration: InputDecoration(
                        hintText: kDefaultHttpUrl,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: TextStyle(fontSize: Theme.of(context).textTheme.labelSmall!.fontSize),
                      keyboardType: TextInputType.url,
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                    ),


                    const SizedBox(height: 20),

                    // Token
                    Text(
                      'Token',
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _tokenController,
                      obscureText: _obscureToken,
                      decoration: InputDecoration(
                        hintText: 'clk_...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureToken
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          tooltip: _obscureToken ? context.l10n.showToken : context.l10n.hideToken,
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                        ),
                      ),
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                        fontFamily: 'monospace',
                      ),
                    ),


                    // 错误提示
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              colorScheme.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                                  color: colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 保存按钮
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: FilledButton(
                        onPressed: _saving ? null : _handleSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                context.l10n.save,
                                style: TextStyle(
                                  fontSize: Theme.of(context).textTheme.bodyMedium!.fontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
