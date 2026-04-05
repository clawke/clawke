import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:client/core/backoff_machine.dart';

enum WsState { connecting, connected, disconnected }

class WsService {
  /// 完整 WS URL（由 ServerConfig 驱动）
  static String _wsUrl = 'ws://127.0.0.1:8780/ws';

  /// 认证 Token
  static String _token = '';

  /// 设置 WebSocket URL
  static void setUrl(String url) => _wsUrl = url;

  /// 设置认证 Token
  static void setToken(String token) => _token = token;

  /// 当前连接 URL（供 UI 显示）
  static String get currentUrl => _wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;
  final _stateController = StreamController<WsState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _backoff = BackoffMachine();
  bool _shouldReconnect = true;

  Stream<WsState> get stateStream => _stateController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  /// 连接成功回调（首次 + 重连都触发，用于 sync 拉增量）
  void Function()? onConnected;

  /// 认证失败回调（CS 返回 401 → token 无效/过期，不自动重连）
  void Function()? onAuthFailed;

  WsState _state = WsState.disconnected;
  WsState get state => _state;

  /// 最近一次连接错误（供 UI 显示）
  String? _lastError;
  String? get lastError => _lastError;

  Future<void> connect() async {
    _setState(WsState.connecting);
    debugPrint('[WS] 🔌 Connecting to $_wsUrl ...');
    try {
      // 取消旧连接的 stream 监听，防止重连时新旧 listener 同时转发导致消息重复
      _channelSub?.cancel();
      _channelSub = null;

      // 拼接 token query param（服务端 WS verifyClient 检查）
      // 注意：不用 Uri.replace()，因为它在原始 URI 无显式 port 时
      // 会把 port 重置为 0，并可能带入 fragment（#），导致连接失败。
      final uri = Uri.parse(_wsUrl);
      // 合并已有 query params + token，并清除 fragment
      final params = Map<String, String>.from(uri.queryParameters);
      if (_token.isNotEmpty) params['token'] = _token;
      // 注意：Uri() 构造函数传 port: null 时会生成 :0 而非协议默认端口。
      // 当原始 URL 无显式端口时，必须让 Dart 自动推导（wss→443, ws→80）。
      final Uri connectUri;
      if (uri.hasPort) {
        connectUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: uri.path,
          queryParameters: params.isEmpty ? null : params,
        );
      } else {
        connectUri = Uri(
          scheme: uri.scheme,
          host: uri.host,
          path: uri.path,
          queryParameters: params.isEmpty ? null : params,
        );
      }
      _channel = WebSocketChannel.connect(connectUri);
      await _channel!.ready;

      _setState(WsState.connected);
      _lastError = null;
      _backoff.reset();
      // 每次连接成功都触发（首次 + 重连），用于发 sync 拉增量
      onConnected?.call();

      _channelSub = _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            _messageController.add(json);
          } catch (_) {}
        },
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          _lastError = 'Disconnected (code=$code'
              '${reason != null && reason.isNotEmpty ? ', reason=$reason' : ''})';
          debugPrint('[WS] 🔌 $_lastError');
          _setState(WsState.disconnected);
          _autoReconnect();
        },
        onError: (e) {
          _lastError = 'Stream error: $e';
          debugPrint('[WS] ❌ $_lastError');
          _setState(WsState.disconnected);
          _autoReconnect();
        },
      );

      // 查询 AI 后端状态（必须在 stream.listen 之后，否则响应会丢失）
      sendJson({'event_type': 'ping'});
    } catch (e) {
      _lastError = '$e';
      debugPrint('[WS] ❌ Connection failed: $_lastError');
      _setState(WsState.disconnected);
      // 检测 401 Unauthorized（token 被拒）→ 不重连，通知 UI
      if (_lastError != null && _lastError!.contains('401')) {
        debugPrint('[WS] 🔒 Auth failed (401), not reconnecting');
        onAuthFailed?.call();
        return;
      }
      _autoReconnect();
    }
  }

  Future<void> _autoReconnect() async {
    if (!_shouldReconnect) return;
    if (_backoff.exhausted) {
      debugPrint('[WS] ⛔ Max retries (${BackoffMachine.maxRetries}) exhausted, stopping auto-reconnect');
      _lastError = '重连次数已达上限，请手动刷新';
      return;
    }
    final attempt = _backoff.attempt + 1;
    final waitTime = _backoff.currentDuration;
    debugPrint('[WS] ⏳ Retry #$attempt in ${(waitTime.inMilliseconds / 1000).toStringAsFixed(1)}s...');
    await _backoff.wait();
    if (_shouldReconnect && _state == WsState.disconnected) {
      connect();
    }
  }

  void send(String jsonString) {
    if (_state == WsState.connected) {
      try {
        _channel?.sink.add(jsonString);
      } catch (_) {}
    }
  }

  /// 发送 JSON 对象（Repository 层使用）
  void sendJson(Map<String, dynamic> json) {
    debugPrint(
      '[WS] 📤 send: ${json['event_type'] ?? json['payload_type'] ?? 'unknown'}',
    );
    send(jsonEncode(json));
  }

  void reconnect() {
    if (_state == WsState.connecting) return;
    debugPrint('[WS] 🔄 Manual reconnect requested');
    _channel?.sink.close();
    connect();
  }

  void _setState(WsState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _shouldReconnect = false;
    _channelSub?.cancel();
    _channel?.sink.close();
    _stateController.close();
    _messageController.close();
  }
}
