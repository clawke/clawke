import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHttpUrlKey = 'clawke_http_url';
const _kWsUrlKey = 'clawke_ws_url';
const _kTokenKey = 'clawke_token';
const _kLoggedOutKey = 'clawke_logged_out';
const kForcedHttpUrl = String.fromEnvironment('CLAWKE_FORCE_HTTP_URL');
const kForcedWsUrl = String.fromEnvironment('CLAWKE_FORCE_WS_URL');
const kForcedToken = String.fromEnvironment('CLAWKE_FORCE_TOKEN');

/// 旧 key（迁移用）
const _kLegacyHostKey = 'clawke_server_host';

/// 默认 URL
const kDefaultHttpUrl = 'http://127.0.0.1:8780';
const kDefaultWsUrl = 'ws://127.0.0.1:8780/ws';

bool shouldUseForcedServerConfig({
  String forcedHttpUrl = kForcedHttpUrl,
  String forcedWsUrl = kForcedWsUrl,
}) {
  return forcedHttpUrl.isNotEmpty && forcedWsUrl.isNotEmpty;
}

String normalizeServerHttpUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return kDefaultHttpUrl;

  var value = trimmed;
  if (value.startsWith('ws://')) {
    value = 'http://${value.substring('ws://'.length)}';
  } else if (value.startsWith('wss://')) {
    value = 'https://${value.substring('wss://'.length)}';
  } else if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }

  final uri = Uri.parse(value);
  final scheme = uri.scheme == 'https' ? 'https' : 'http';
  final path = _normalizeServerBasePath(uri.path);
  return _uriWithOptionalPort(
    scheme: scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

Future<void> applyForcedServerConfig(SharedPreferences prefs) async {
  if (!shouldUseForcedServerConfig()) return;
  // 调试覆盖服务器地址，便于真机连接本机 Server — Debug-only server override for device testing.
  await prefs.setString(_kHttpUrlKey, kForcedHttpUrl);
  await prefs.setString(_kWsUrlKey, kForcedWsUrl);
  if (kForcedToken.isEmpty) {
    await prefs.remove(_kTokenKey);
  } else {
    // 调试直连认证 token，适用于本地 dev Server — Debug-only auth token for local dev Server.
    await prefs.setString(_kTokenKey, kForcedToken);
  }
}

String deriveWsUrlFromServerAddress(String url) {
  final httpUrl = normalizeServerHttpUrl(url);
  final uri = Uri.parse(httpUrl);
  final basePath = _normalizeServerBasePath(uri.path);
  final wsPath = basePath.isEmpty ? '/ws' : '$basePath/ws';
  return _uriWithOptionalPort(
    scheme: uri.scheme == 'https' ? 'wss' : 'ws',
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: wsPath,
  ).toString();
}

String _normalizeServerBasePath(String path) {
  var normalized = path;
  if (normalized == '/ws') normalized = '';
  if (normalized.endsWith('/ws')) {
    normalized = normalized.substring(0, normalized.length - '/ws'.length);
  }
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized == '/' ? '' : normalized;
}

Uri _uriWithOptionalPort({
  required String scheme,
  required String host,
  required String path,
  int? port,
}) {
  if (port != null) {
    return Uri(scheme: scheme, host: host, port: port, path: path);
  }
  return Uri(scheme: scheme, host: host, path: path);
}

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
    StateNotifierProvider<ServerConfigNotifier, ServerConfig>(
      (ref) => ServerConfigNotifier(),
    );

class ServerConfigNotifier extends StateNotifier<ServerConfig> {
  ServerConfigNotifier({
    ServerConfig initialConfig = const ServerConfig(),
    bool loadFromPrefs = true,
  }) : super(initialConfig) {
    if (loadFromPrefs) {
      _load();
    } else {
      _loadCompleter.complete(state);
    }
  }

  final Completer<ServerConfig> _loadCompleter = Completer<ServerConfig>();

  /// 等待 SharedPreferences 加载完成，返回最终配置
  Future<ServerConfig> ensureLoaded() => _loadCompleter.future;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (shouldUseForcedServerConfig()) {
      await applyForcedServerConfig(prefs);
      state = const ServerConfig(
        httpUrl: kForcedHttpUrl,
        wsUrl: kForcedWsUrl,
        token: kForcedToken,
      );
      _loadCompleter.complete(state);
      return;
    }

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

    final normalizedHttpUrl = (httpUrl != null && httpUrl.isNotEmpty)
        ? normalizeServerHttpUrl(httpUrl)
        : kDefaultHttpUrl;
    var normalizedWsUrl = (migratedWsUrl != null && migratedWsUrl.isNotEmpty)
        ? migratedWsUrl.trim()
        : deriveWsUrlFromServerAddress(normalizedHttpUrl);
    if (normalizedWsUrl.startsWith('http://') ||
        normalizedWsUrl.startsWith('https://') ||
        normalizedWsUrl.contains('/ws/ws')) {
      normalizedWsUrl = deriveWsUrlFromServerAddress(normalizedHttpUrl);
    }

    if (httpUrl != normalizedHttpUrl) {
      await prefs.setString(_kHttpUrlKey, normalizedHttpUrl);
    }
    if (wsUrl != normalizedWsUrl) {
      await prefs.setString(_kWsUrlKey, normalizedWsUrl);
    }

    state = ServerConfig(
      httpUrl: normalizedHttpUrl,
      wsUrl: normalizedWsUrl,
      token: token,
    );
    _loadCompleter.complete(state);
  }

  Future<void> setHttpUrl(String url) async {
    final trimmed = normalizeServerHttpUrl(url);
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

    final httpUrl = normalizeServerHttpUrl(trimmed);
    final wsUrl = deriveWsUrlFromServerAddress(httpUrl);
    await setBoth(httpUrl: httpUrl, wsUrl: wsUrl);
    // A token belongs to a specific server/relay. Clear it on address changes
    // so manual local connections do not leak or reuse stale relay tokens.
    await setToken('');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLoggedOutKey);
  }
}
