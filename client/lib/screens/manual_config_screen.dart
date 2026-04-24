import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:client/providers/server_host_provider.dart';
import 'package:client/l10n/l10n.dart';

/// Full-screen manual server configuration page.
///
/// User enters server URL + optional token, clicks "连接" to test
/// the WebSocket connection. Only navigates to MainLayout on success.
class ManualConfigScreen extends ConsumerStatefulWidget {
  const ManualConfigScreen({super.key});

  @override
  ConsumerState<ManualConfigScreen> createState() => _ManualConfigScreenState();
}

class _ManualConfigScreenState extends ConsumerState<ManualConfigScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isConnecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 从已保存的配置预填（与设置页共享 SharedPreferences）
    final config = ref.read(serverConfigProvider);
    if (config.httpUrl != kDefaultHttpUrl) {
      _urlController.text = config.httpUrl;
    }
    if (config.token.isNotEmpty) {
      _tokenController.text = config.token;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.manualConfigTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  context.l10n.serverConnection,
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.titleMedium!.fontSize,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.enterServerAddressToConnect,
                  style: TextStyle(
                    fontSize: Theme.of(context).textTheme.bodySmall!.fontSize,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),

                const SizedBox(height: 24),

                // Server URL
                TextField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: context.l10n.serverAddress,
                    hintText: 'http://192.168.1.100:8780',

                    prefixIcon: const Icon(Icons.dns_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                  ),
                ),

                const SizedBox(height: 16),

                // Token（不可见）
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.tokenOptional,
                    hintText: context.l10n.tokenHint,
                    prefixIcon: const Icon(Icons.key_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                  ),
                ),

                const SizedBox(height: 24),

                // Error message
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: colorScheme.error, fontSize: Theme.of(context).textTheme.bodySmall!.fontSize),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Connect button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _isConnecting ? null : _handleConnect,
                    icon: _isConnecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                      _isConnecting ? context.l10n.connectingStatus : context.l10n.manualConfigConnect,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleConnect() async {
    final l10n = context.l10n;
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = l10n.enterServerAddressError);
      return;
    }

    setState(() { _isConnecting = true; _error = null; });

    try {
      // Derive WS URL from HTTP URL
      String wsUrl;
      if (url.startsWith('https://')) {
        wsUrl = '${url.replaceFirst('https://', 'wss://')}/ws';
      } else if (url.startsWith('http://')) {
        wsUrl = '${url.replaceFirst('http://', 'ws://')}/ws';
      } else {
        wsUrl = 'ws://$url/ws';
      }

      // Append token as query param (same as ws_service.dart)
      final token = _tokenController.text.trim();
      final wsUri = Uri.parse(wsUrl);
      final connectUri = token.isNotEmpty
          ? wsUri.replace(queryParameters: {...wsUri.queryParameters, 'token': token})
          : wsUri;

      // Test WebSocket connection with timeout
      final channel = WebSocketChannel.connect(connectUri);
      await channel.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(l10n.connectionTimeout),
      );
      await channel.sink.close();

      // Connection successful — save config and navigate
      await ref.read(serverConfigProvider.notifier).setServerAddress(url);
      await ref.read(serverConfigProvider.notifier).setToken(token);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
    } on TimeoutException catch (e) {
      if (mounted) setState(() => _error = e.message ?? l10n.connectionTimeoutShort);
    } on SocketException catch (e) {
      if (mounted) setState(() => _error = l10n.connectionFailed(e.message));
    } catch (e) {
      if (mounted) setState(() => _error = l10n.connectionFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }
}
