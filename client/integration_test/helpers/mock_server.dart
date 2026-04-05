import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 进程内 Mock WebSocket Server，用于集成测试
class MockServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final List<Map<String, dynamic>> received = [];
  final List<Map<String, dynamic>> _queue = [];

  Future<void> start({int port = 8765}) async {
    _server = await HttpServer.bind('127.0.0.1', port);
    _server!.transform(WebSocketTransformer()).listen((ws) {
      _clients.add(ws);

      // 发送排队的响应
      for (final json in _queue) {
        ws.add(jsonEncode(json));
      }
      _queue.clear();

      ws.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            received.add(json);
          } catch (_) {}
        },
        onDone: () => _clients.remove(ws),
        onError: (_) => _clients.remove(ws),
      );
    });
  }

  /// 排队一条响应（客户端连接后会收到）
  void enqueueResponse(Map<String, dynamic> json) {
    if (_clients.isNotEmpty) {
      for (final ws in _clients) {
        ws.add(jsonEncode(json));
      }
    } else {
      _queue.add(json);
    }
  }

  /// 向所有已连接客户端广播
  void broadcast(Map<String, dynamic> json) {
    for (final ws in _clients) {
      ws.add(jsonEncode(json));
    }
  }

  Future<void> stop() async {
    for (final ws in _clients) {
      await ws.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    received.clear();
    _queue.clear();
  }
}
