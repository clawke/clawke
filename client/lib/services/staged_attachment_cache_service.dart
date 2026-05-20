import 'package:client/providers/staged_attachments_provider.dart';
import 'package:client/services/media_cache_service.dart';

typedef CacheFileForSend = String Function(String sourcePath);
typedef CacheBytesForSend = String Function(List<int> bytes, String fileName);
typedef FallbackFileNameFactory = String Function();

String cacheStagedAttachmentForSend(
  StagedAttachment attachment, {
  CacheFileForSend? cacheFile,
  CacheBytesForSend? cacheBytes,
  FallbackFileNameFactory? fallbackFileName,
}) {
  final path = attachment.path;
  if (path != null && path.isNotEmpty) {
    return (cacheFile ?? MediaCacheService.instance.cacheFileSync)(path);
  }

  final bytes = attachment.bytes;
  if (bytes != null && bytes.isNotEmpty) {
    final name = attachment.name?.isNotEmpty == true
        ? attachment.name!
        : (fallbackFileName?.call() ??
              'paste_${DateTime.now().millisecondsSinceEpoch}.png');
    return (cacheBytes ?? MediaCacheService.instance.cacheBytes)(bytes, name);
  }

  return '';
}
