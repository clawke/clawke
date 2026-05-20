import 'dart:convert';
import 'dart:io';

import 'package:client/providers/staged_attachments_provider.dart';
import 'package:client/services/media_upload_service.dart';
import 'package:client/services/staged_attachment_cache_service.dart';

typedef MixedMediaUpload = Future<MediaUploadResult> Function(File file);

String buildLocalMixedContentJson(
  String text,
  List<StagedAttachment> attachments, {
  CacheFileForSend? cacheFile,
  CacheBytesForSend? cacheBytes,
}) {
  final atts = <Map<String, dynamic>>[];
  for (final attachment in attachments) {
    final cachedPath = cacheStagedAttachmentForSend(
      attachment,
      cacheFile: cacheFile,
      cacheBytes: cacheBytes,
    );
    if (cachedPath.isEmpty) continue;

    if (attachment.isImage) {
      atts.add({'type': 'image', 'path': cachedPath});
    } else {
      atts.add({
        'type': 'file',
        'path': cachedPath,
        'name': attachment.name ?? 'unknown',
        'size': attachment.size ?? 0,
      });
    }
  }
  return jsonEncode({'text': text, 'attachments': atts});
}

Future<String> buildUploadedMixedContentJson(
  String text,
  List<StagedAttachment> attachments, {
  required MixedMediaUpload upload,
  CacheFileForSend? cacheFile,
  CacheBytesForSend? cacheBytes,
  void Function(MediaUploadResult result)? onUploadSuccess,
  void Function(Object error)? onUploadError,
}) async {
  final atts = <Map<String, dynamic>>[];

  for (final attachment in attachments) {
    final cachedPath = cacheStagedAttachmentForSend(
      attachment,
      cacheFile: cacheFile,
      cacheBytes: cacheBytes,
    );
    if (cachedPath.isEmpty) continue;

    try {
      final result = await upload(File(cachedPath));
      onUploadSuccess?.call(result);

      if (attachment.isImage) {
        atts.add({
          'type': 'image',
          'mediaUrl': result.mediaUrl,
          'thumbUrl': result.thumbUrl,
          'thumbHash': result.thumbHash,
          'width': result.width,
          'height': result.height,
          'localPath': cachedPath,
        });
      } else {
        atts.add({
          'type': 'file',
          'mediaUrl': result.mediaUrl,
          'mediaType': result.mediaType ?? 'application/octet-stream',
          'name': attachment.name ?? 'unknown',
          'size': attachment.size ?? 0,
          'localPath': cachedPath,
        });
      }
    } catch (error) {
      onUploadError?.call(error);
      if (attachment.isImage) {
        atts.add({'type': 'image', 'path': cachedPath});
      } else {
        atts.add({
          'type': 'file',
          'path': cachedPath,
          'name': attachment.name ?? 'unknown',
          'size': attachment.size ?? 0,
        });
      }
    }
  }

  return jsonEncode({'text': text, 'attachments': atts});
}
