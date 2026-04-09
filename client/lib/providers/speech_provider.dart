import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/services/speech_service.dart';

/// 单例 SpeechService
final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService();
});

/// 当前是否正在录音
final isListeningProvider = StateProvider<bool>((ref) => false);

/// 当前是否正在转写（上传中）
final isTranscribingProvider = StateProvider<bool>((ref) => false);
