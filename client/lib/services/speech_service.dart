import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:flutter/foundation.dart';

/// 语音识别服务 — 封装 speech_to_text 插件
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  String _localeId = 'zh_CN';

  /// 最近一次错误信息（用于 UI 展示）
  String? lastError;

  /// 状态变更回调（用于同步 Riverpod 状态）
  void Function(bool isListening)? onListeningChanged;

  bool get isAvailable => _isInitialized;
  bool get isListening => _speech.isListening;

  /// 初始化语音识别引擎
  Future<bool> init() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (e) {
      debugPrint('[SpeechService] Init exception: $e');
      lastError = e.toString();
      return false;
    }

    if (_isInitialized) {
      final locales = await _speech.locales();
      debugPrint('[SpeechService] Available locales: ${locales.map((l) => l.localeId).join(', ')}');
      debugPrint('[SpeechService] Initialized OK');
    } else {
      debugPrint('[SpeechService] Init returned false — speech recognition not available on this device');
      lastError = '语音识别引擎不可用';
    }

    return _isInitialized;
  }

  void _handleError(SpeechRecognitionError error) {
    debugPrint('[SpeechService] ❌ Error: ${error.errorMsg} (permanent: ${error.permanent})');
    lastError = error.errorMsg;
    if (error.permanent) {
      onListeningChanged?.call(false);
    }
  }

  void _handleStatus(String status) {
    debugPrint('[SpeechService] 📊 Status: $status');
    // "notListening" 表示引擎已停止（超时/错误/主动停止）
    if (status == 'notListening') {
      onListeningChanged?.call(false);
    }
  }

  /// 根据 App 当前语言设置识别 locale
  /// languageCode: 'zh' → zh_CN, 'en' → en_US
  Future<void> updateLocale(String languageCode) async {
    if (!_isInitialized) return;

    final locales = await _speech.locales();
    final prefix = languageCode == 'zh' ? 'zh' : 'en';

    final matched = locales.firstWhere(
      (l) => l.localeId.startsWith(prefix),
      orElse: () => locales.first,
    );
    _localeId = matched.localeId;
    debugPrint('[SpeechService] Locale set to: $_localeId');
  }

  /// 开始监听语音
  Future<void> startListening({
    required void Function(SpeechRecognitionResult result) onResult,
  }) async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) return;
    }

    lastError = null;
    debugPrint('[SpeechService] 🎤 Starting listening with locale: $_localeId');

    await _speech.listen(
      onResult: (result) {
        debugPrint('[SpeechService] 📝 Result: "${result.recognizedWords}" (final: ${result.finalResult})');
        onResult(result);
      },
      localeId: _localeId,
      listenMode: ListenMode.dictation,  // 长句模式
      cancelOnError: false,
      partialResults: true,  // 实时返回部分结果
      listenFor: const Duration(seconds: 30),  // 最长听 30 秒
      pauseFor: const Duration(seconds: 3),    // 静默 3 秒后停止
    );
  }

  /// 停止监听
  Future<void> stopListening() async {
    debugPrint('[SpeechService] ⏹ Stop listening');
    await _speech.stop();
  }

  /// 取消监听（丢弃结果）
  Future<void> cancel() async {
    await _speech.cancel();
  }
}
