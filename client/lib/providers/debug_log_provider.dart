import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDebugLogEnabledKey = 'clawke_debug_log_enabled';

/// 控制调试日志面板是否显示（持久化）
class DebugLogEnabledNotifier extends StateNotifier<bool> {
  DebugLogEnabledNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kDebugLogEnabledKey);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDebugLogEnabledKey, state);
  }

  void toggle() {
    state = !state;
    _save();
  }

  void setEnabled(bool value) {
    state = value;
    _save();
  }
}

final debugLogEnabledProvider =
    StateNotifierProvider<DebugLogEnabledNotifier, bool>(
      (ref) => DebugLogEnabledNotifier(),
    );

/// 调试日志消息列表
class DebugLogNotifier extends StateNotifier<List<String>> {
  DebugLogNotifier() : super([]);

  /// 全局单例（供 debugPrint 覆盖使用，不依赖 Riverpod）
  static final instance = DebugLogNotifier();

  /// 添加一条日志
  void addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    state = [...state, '[$timestamp] $message'];
    // 限制最大条数，防止内存溢出
    if (state.length > 500) {
      state = state.sublist(state.length - 500);
    }
  }

  /// 清除所有日志
  void clearLogs() {
    state = [];
  }
}

final debugLogMessagesProvider =
    StateNotifierProvider<DebugLogNotifier, List<String>>((ref) {
      return DebugLogNotifier.instance;
    });
