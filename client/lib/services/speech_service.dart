import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter/foundation.dart';

/// 语音识别服务 — 封装 speech_to_text 插件
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  String _localeId = 'zh_CN';

  bool get isAvailable => _isInitialized;
  bool get isListening => _speech.isListening;

  /// 初始化语音识别引擎
  Future<bool> init() async {
    if (_isInitialized) return true;

    _isInitialized = await _speech.initialize(
      onError: (error) {
        debugPrint('[SpeechService] Error: ${error.errorMsg}');
      },
      onStatus: (status) {
        debugPrint('[SpeechService] Status: $status');
      },
    );

    if (_isInitialized) {
      debugPrint('[SpeechService] Initialized, default locale: $_localeId');
    }

    return _isInitialized;
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
    debugPrint('[SpeechService] Locale updated to: $_localeId');
  }

  /// 开始监听语音
  Future<void> startListening({
    required void Function(SpeechRecognitionResult result) onResult,
  }) async {
    if (!_isInitialized) {
      final ok = await init();
      if (!ok) return;
    }

    await _speech.listen(
      onResult: onResult,
      localeId: _localeId,
      listenMode: ListenMode.dictation,  // 长句模式
      cancelOnError: false,
      partialResults: true,  // 实时返回部分结果
    );
  }

  /// 停止监听
  Future<void> stopListening() async {
    await _speech.stop();
  }

  /// 取消监听（丢弃结果）
  Future<void> cancel() async {
    await _speech.cancel();
  }
}
