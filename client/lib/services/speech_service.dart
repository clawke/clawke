import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

/// 语音识别服务 — 录音 + Groq Whisper API 转写
class SpeechService {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;

  /// 最近一次错误
  String? lastError;

  /// 录音状态
  bool get isRecording => _isRecording;

  /// 检查录音权限
  Future<bool> checkPermission() async {
    return await _recorder.hasPermission();
  }

  /// 开始录音
  Future<bool> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        lastError = '未授予录音权限';
        debugPrint('[SpeechService] ❌ No recording permission');
        return false;
      }

      final dir = await getTemporaryDirectory();
      _audioPath = '${dir.path}/stt_audio.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
        path: _audioPath!,
      );

      _isRecording = true;
      lastError = null;
      debugPrint('[SpeechService] 🎤 Recording started → $_audioPath');
      return true;
    } catch (e) {
      lastError = '录音启动失败: $e';
      debugPrint('[SpeechService] ❌ Start recording failed: $e');
      return false;
    }
  }

  /// 停止录音并返回文件路径
  Future<String?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;
      debugPrint('[SpeechService] ⏹ Recording stopped: $path');
      return path;
    } catch (e) {
      _isRecording = false;
      lastError = '录音停止失败: $e';
      debugPrint('[SpeechService] ❌ Stop recording failed: $e');
      return null;
    }
  }

  /// 上传音频到服务器进行 STT 转写
  Future<String?> transcribe({
    required String audioPath,
    required String serverUrl,
    required String token,
  }) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        lastError = '录音文件不存在';
        return null;
      }

      final fileSize = await file.length();
      debugPrint('[SpeechService] 📤 Uploading ${(fileSize / 1024).toStringAsFixed(1)}KB to $serverUrl/api/stt');

      final uri = Uri.parse('$serverUrl/api/stt');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath(
          'audio',
          audioPath,
          contentType: MediaType('audio', 'wav'),
        ));

      final stopwatch = Stopwatch()..start();
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      stopwatch.stop();

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final text = body['text'] as String? ?? '';
        debugPrint('[SpeechService] ✅ Transcribed in ${stopwatch.elapsedMilliseconds}ms: "$text"');
        return text;
      } else {
        lastError = 'STT 错误 (${response.statusCode})';
        debugPrint('[SpeechService] ❌ STT API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      lastError = '转写失败: $e';
      debugPrint('[SpeechService] ❌ Transcribe error: $e');
      return null;
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
