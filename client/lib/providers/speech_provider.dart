import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/services/speech_service.dart';

/// 单例 SpeechService
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService();
});

/// 当前是否正在监听语音
final isListeningProvider = StateProvider<bool>((ref) => false);

/// 当前语音识别的临时文本（partial result）
/// 用于在输入框中实时显示正在说的内容
final speechPartialTextProvider = StateProvider<String>((ref) => '');
