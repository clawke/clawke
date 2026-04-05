import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:client/services/media_resolver.dart';

/// HTTP 媒体上传服务
///
/// 将文件通过 HTTP multipart/form-data 上传到 CS HTTP Server。
/// 使用 dio 获取真实上传进度（替代旧的 http 包模拟进度）。
class MediaUploadService {
  final String baseUrl;

  MediaUploadService({required this.baseUrl});

  /// 上传文件到 CS
  ///
  /// 返回 [MediaUploadResult]，包含 mediaUrl、thumbUrl、thumbHash 等。
  /// [onProgress] 回调参数为 0.0 ~ 1.0 的上传进度（真实字节级）。
  Future<MediaUploadResult> upload(
    File file, {
    void Function(double progress)? onProgress,
  }) async {
    final url = '$baseUrl/api/media/upload';
    final fileName = p.basename(file.path);
    final fileSize = await file.length();

    debugPrint(
      '[MediaUpload] Uploading $fileName (${(fileSize / 1024).toStringAsFixed(1)}KB) to $url',
    );

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 120),
      headers: MediaResolver.authHeaders,
    ));

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: _inferDioContentType(fileName),
      ),
    });

    final response = await dio.post(
      url,
      data: formData,
      onSendProgress: (sent, total) {
        if (total > 0) {
          onProgress?.call(sent / total);
        }
      },
    );

    if (response.statusCode != 200) {
      throw MediaUploadException(
        'Upload failed: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final json = response.data as Map<String, dynamic>;

    debugPrint(
      '[MediaUpload] OK: mediaUrl=${json['mediaUrl']}, thumbHash=${json['thumbHash'] != null}',
    );

    return MediaUploadResult(
      mediaId: json['mediaId'] as String? ?? '',
      mediaUrl: json['mediaUrl'] as String? ?? '',
      mediaType: json['mediaType'] as String?,
      thumbUrl: json['thumbUrl'] as String?,
      thumbHash: json['thumbHash'] as String?,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
    );
  }

  /// 推断 Content-Type（dio 使用 DioMediaType）
  DioMediaType? _inferDioContentType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    return switch (ext) {
      '.jpg' || '.jpeg' => DioMediaType('image', 'jpeg'),
      '.png' => DioMediaType('image', 'png'),
      '.gif' => DioMediaType('image', 'gif'),
      '.webp' => DioMediaType('image', 'webp'),
      '.pdf' => DioMediaType('application', 'pdf'),
      _ => DioMediaType('application', 'octet-stream'),
    };
  }
}

/// 上传结果
class MediaUploadResult {
  final String mediaId;
  final String mediaUrl; // /api/media/xxx.png (相对路径)
  final String? mediaType; // MIME type (e.g. image/png, application/pdf)
  final String? thumbUrl; // /api/media/thumb/xxx.jpg
  final String? thumbHash; // base64 (~28 bytes)
  final int? width;
  final int? height;

  const MediaUploadResult({
    required this.mediaId,
    required this.mediaUrl,
    this.mediaType,
    this.thumbUrl,
    this.thumbHash,
    this.width,
    this.height,
  });

  @override
  String toString() =>
      'MediaUploadResult(mediaUrl=$mediaUrl, mediaType=$mediaType, thumbHash=${thumbHash != null}, ${width}x$height)';
}

/// 上传异常
class MediaUploadException implements Exception {
  final String message;
  final int? statusCode;

  const MediaUploadException(this.message, {this.statusCode});

  @override
  String toString() => 'MediaUploadException: $message';
}
