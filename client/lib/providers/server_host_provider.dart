import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHttpUrlKey = 'clawke_http_url';
const _kWsUrlKey = 'clawke_ws_url';
const _kTokenKey = 'clawke_token';

/// 旧 key（迁移用）
const _kLegacyHostKey = 'clawke_server_host';

/// 默认 URL
const kDefaultHttpUrl = 'http://127.0.0.1:8780';
const kDefaultWsUrl = 'ws://127.0.0.1:8780/ws';

/// Clawke 服务器连接配置
///
/// 持久化两个独立的完整 URL（含协议、IP、端口）：
/// - HTTP URL：用于媒体上传/下载（MediaResolver）
/// - WS URL：用于 WebSocket 连接（WsService）
///
/// 支持未来切换为 https/wss（iOS 正式发布要求）。
class ServerConfig {
  final String httpUrl;
  final String wsUrl;
  final String token;

  const ServerConfig({
    this.httpUrl = kDefaultHttpUrl,
    this.wsUrl = kDefaultWsUrl,
    this.token = '',
  });

  ServerConfig copyWith({String? httpUrl, String? wsUrl, String? token}) {
    return ServerConfig(
      httpUrl: httpUrl ?? this.httpUrl,
      wsUrl: wsUrl ?? this.wsUrl,
      token: token ?? this.token,
    );
  }
}

/// 服务器配置 Provider（持久化到 SharedPreferences）
final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, ServerConfig>((ref) {
  return ServerConfigNotifier();
});

class ServerConfigNotifier extends StateNotifier<ServerConfig> {
  ServerConfigNotifier() : super(const ServerConfig()) {
    _load();
  }

  final Completer<ServerConfig> _loadCompleter = Completer<ServerConfig>();

  /// 等待 SharedPreferences 加载完成，返回最终配置
  Future<ServerConfig> ensureLoaded() => _loadCompleter.future;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // 兼容迁移：旧版只存了 host，自动生成两个 URL 并清除旧 key
    final legacyHost = prefs.getString(_kLegacyHostKey);
    if (legacyHost != null && legacyHost.isNotEmpty) {
      final httpUrl = 'http://$legacyHost:8780';
      final wsUrl = 'ws://$legacyHost:8780/ws';
      await prefs.setString(_kHttpUrlKey, httpUrl);
      await prefs.setString(_kWsUrlKey, wsUrl);
      await prefs.remove(_kLegacyHostKey);
      final token = prefs.getString(_kTokenKey) ?? '';
      state = ServerConfig(httpUrl: httpUrl, wsUrl: wsUrl, token: token);
      _loadCompleter.complete(state);
      return;
    }

    final httpUrl = prefs.getString(_kHttpUrlKey);
    final wsUrl = prefs.getString(_kWsUrlKey);
    final token = prefs.getString(_kTokenKey) ?? '';

    // 端口统一迁移：旧版 WS 用 8765，新版统一到 8780/ws
    String? migratedWsUrl = wsUrl;
    if (wsUrl != null && wsUrl.contains(':8765') && !wsUrl.contains('/ws')) {
      migratedWsUrl = wsUrl.replaceFirst(':8765', ':8780/ws');
      await prefs.setString(_kWsUrlKey, migratedWsUrl);
    }

    state = ServerConfig(
      httpUrl: (httpUrl != null && httpUrl.isNotEmpty) ? httpUrl : kDefaultHttpUrl,
      wsUrl: (migratedWsUrl != null && migratedWsUrl.isNotEmpty) ? migratedWsUrl : kDefaultWsUrl,
      token: token,
    );
    _loadCompleter.complete(state);
  }

  Future<void> setHttpUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(httpUrl: trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHttpUrlKey, trimmed);
  }

  Future<void> setWsUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(wsUrl: trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWsUrlKey, trimmed);
  }

  /// 设置 Token并持久化
  Future<void> setToken(String token) async {
    final trimmed = token.trim();
    state = state.copyWith(token: trimmed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenKey, trimmed);
  }

  Future<void> setBoth({required String httpUrl, required String wsUrl}) async {
    final h = httpUrl.trim();
    final w = wsUrl.trim();
    if (h.isEmpty || w.isEmpty) return;
    state = state.copyWith(httpUrl: h, wsUrl: w);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHttpUrlKey, h);
    await prefs.setString(_kWsUrlKey, w);
  }

  /// 从完整 URL（含协议）自动推导 httpUrl + wsUrl
  ///
  /// - `http://192.168.1.100:8780` → ws://192.168.1.100:8780/ws
  /// - `https://abc.relay.clawke.ai` → wss://abc.relay.clawke.ai/ws
  Future<void> setServerAddress(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    final httpUrl = trimmed;
    String wsUrl;

    if (trimmed.startsWith('https://')) {
      wsUrl = '${trimmed.replaceFirst('https://', 'wss://')}/ws';
    } else if (trimmed.startsWith('http://')) {
      wsUrl = '${trimmed.replaceFirst('http://', 'ws://')}/ws';
    } else {
      // 没有协议前缀，默认 http
      wsUrl = 'ws://$trimmed/ws';
    }

    await setBoth(httpUrl: httpUrl, wsUrl: wsUrl);
    // A token belongs to a specific server/relay. Clear it on address changes
    // so manual local connections do not leak or reuse stale relay tokens.
    await setToken('');
  }
}
