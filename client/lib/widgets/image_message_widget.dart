import 'dart:io';
import 'package:flutter/material.dart';
import 'progressive_image.dart';

/// 聊天图片消息组件
///
/// 支持两种模式：
/// 1. 新架构：mediaUrl + thumbUrl + thumbHash → 委托 ProgressiveImage 三层渐进加载
/// 2. 旧兼容：filePath → 直接显示本地文件
class ImageMessageWidget extends StatelessWidget {
  /// 旧接口兼容：本地文件路径
  final String? filePath;

  /// 新架构：HTTP 相对路径（如 /api/media/xxx.png）
  final String? mediaUrl;
  final String? thumbUrl;
  final String? thumbHash;
  final int? width;
  final int? height;
  /// 下载缓存成功后的回调，用于将 localPath 写回 DB
  final void Function(String cachedPath)? onCached;

  const ImageMessageWidget({
    super.key,
    this.filePath,
    this.mediaUrl,
    this.thumbUrl,
    this.thumbHash,
    this.width,
    this.height,
    this.onCached,
  });

  @override
  Widget build(BuildContext context) {
    // 新架构：有任何 progressive loading 参数 → 使用 ProgressiveImage
    if (mediaUrl != null || thumbUrl != null || thumbHash != null) {
      return ProgressiveImage(
        localPath: filePath,
        fullUrl: mediaUrl,
        thumbUrl: thumbUrl,
        thumbHash: thumbHash,
        width: width,
        height: height,
        onCached: onCached,
      );
    }

    // 旧兼容：filePath → 直接显示本地文件
    if (filePath != null) {
      return _buildLegacyImage(context);
    }

    return _buildPlaceholder(context);
  }

  Widget _buildLegacyImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
          child: () {
            final file = File(filePath!);
            if (file.existsSync()) {
              return Image.file(file, fit: BoxFit.cover);
            }
            return Container(
              width: 200,
              height: 150,
              color: colorScheme.surfaceContainerLowest,
              child: Icon(
                Icons.broken_image,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
            );
          }(),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      height: 150,
      color: colorScheme.surfaceContainerLowest,
      child: Icon(Icons.image, size: 48, color: colorScheme.onSurfaceVariant),
    );
  }

  void _showFullScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            child: filePath != null
                ? Image.file(File(filePath!), fit: BoxFit.contain)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
