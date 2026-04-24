import 'dart:math';

/// 指数退避 + 抖动（参考 Zulip BackoffMachine）
class BackoffMachine {
  static const _firstDuration = Duration(milliseconds: 100);
  static const _maxDuration = Duration(seconds: 60);
  static const _base = 2.0;
  /// 超过此次数后停止自动重试
  static const maxRetries = 50;

  final _random = Random();
  int _attempt = 0;

  /// 当前重试次数
  int get attempt => _attempt;

  /// 是否已超过最大重试次数
  bool get exhausted => _attempt >= maxRetries;

  /// 等待当前退避时间后返回，返回实际等待的时长
  Future<Duration> wait() async {
    final duration = currentDuration;
    _attempt++;
    await Future.delayed(duration);
    return duration;
  }

  /// 当前退避时长（供日志使用）
  Duration get currentDuration => _computeDuration();

  Duration _computeDuration() {
    final exponential = _firstDuration * pow(_base, _attempt);
    final capped = exponential > _maxDuration ? _maxDuration : exponential;
    // 添加 ±25% 抖动
    final jitter = capped.inMilliseconds * (0.75 + _random.nextDouble() * 0.5);
    return Duration(milliseconds: jitter.round());
  }

  /// 连接成功后重置
  void reset() => _attempt = 0;
}
