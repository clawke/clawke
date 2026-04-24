// 文件日志工具 — 将关键 WS 消息路由信息写入文件，用于排查跨会话路由 Bug
//
// 所有平台统一使用 getApplicationSupportDirectory：
//   macOS:   ~/Library/Containers/ai.clawke.app/Data/Library/Application Support/ai.clawke.app/logs/
//   Windows: C:\Users\<user>\AppData\Roaming\ai.clawke.app\logs\
//   Linux:   ~/.local/share/ai.clawke.app/logs/
//   iOS/Android: <app sandbox>/logs/
//
// 文件名：client-YYYY-MM-DD.log
// 仅记录关键路由事件，不会过度写入
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileLogger {
  FileLogger._();
  static final FileLogger instance = FileLogger._();

  File? _logFile;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${appDir.path}/logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      _logFile = File('${logDir.path}/client-$date.log');
      _initialized = true;
      debugPrint('[FileLogger] 📂 Log path: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[FileLogger] ❌ Init failed: $e');
    }
  }

  /// 写入一行日志（异步，不阻塞 UI）
  void log(String message) {
    init().then((_) {
      final ts = DateTime.now().toIso8601String();
      _logFile?.writeAsStringSync(
        '[$ts] $message\n',
        mode: FileMode.append,
        flush: false,
      );
    });
  }

  /// 获取日志文件路径（供调试用）
  Future<String?> get logPath async {
    await init();
    return _logFile?.path;
  }
}
