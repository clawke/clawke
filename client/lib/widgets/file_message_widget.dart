import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:client/services/media_cache_service.dart';
import 'package:client/services/media_resolver.dart';

/// 文件消息组件
///
/// 支持三种状态：
/// 1. 本地有文件 → 点击直接打开
/// 2. 本地无文件 + 有 mediaUrl → 点击下载后打开
/// 3. 都没有 → 不可点击（显示文件信息）
class FileMessageWidget extends StatefulWidget {
  final String fileName;
  final String? filePath;
  final String? mediaUrl;
  final int? fileSize;
  /// 下载缓存成功后的回调，用于将 localPath 写回 DB
  final void Function(String cachedPath)? onCached;

  const FileMessageWidget({
    super.key,
    required this.fileName,
    this.filePath,
    this.mediaUrl,
    this.fileSize,
    this.onCached,
  });

  @override
  State<FileMessageWidget> createState() => _FileMessageWidgetState();
}

class _FileMessageWidgetState extends State<FileMessageWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _localPath = widget.filePath;
  }

  @override
  void didUpdateWidget(FileMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // DB content 更新后（如上传完成后 JSON 变化），同步 _localPath
    if (widget.filePath != oldWidget.filePath) {
      _localPath = widget.filePath;
    }
  }

  bool get _hasLocalFile {
    if (_localPath == null) return false;
    return File(_localPath!).existsSync();
  }

  bool get _canDownload {
    return widget.mediaUrl != null && widget.mediaUrl!.isNotEmpty;
  }

  Future<void> _handleTap() async {
    if (_isDownloading) return;

    debugPrint('[FileMessage] Tap: localPath=$_localPath, '
        'filePath=${widget.filePath}, mediaUrl=${widget.mediaUrl}, '
        'hasLocal=$_hasLocalFile, canDownload=$_canDownload');

    // 本地有文件 → 直接打开
    if (_hasLocalFile) {
      debugPrint('[FileMessage] Opening local file: $_localPath');
      final result = await OpenFilex.open(_localPath!);
      debugPrint('[FileMessage] OpenFilex result: type=${result.type}, message=${result.message}');
      return;
    }

    // 本地没有 + 有 mediaUrl → 下载后打开
    if (_canDownload) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0;
      });

      try {
        final resolvedUrl = MediaResolver.resolve(widget.mediaUrl!);
        final cachedPath = await MediaCacheService.instance.downloadAndCache(
          resolvedUrl,
        );

        if (cachedPath != null && mounted) {
          setState(() {
            _localPath = cachedPath;
            _isDownloading = false;
            _downloadProgress = 1.0;
          });
          // 写回 DB，下次重建 widget 不再重复下载
          widget.onCached?.call(cachedPath);
          await OpenFilex.open(cachedPath);
        } else if (mounted) {
          setState(() => _isDownloading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载失败')),
            );
          }
        }
      } catch (e) {
        debugPrint('[FileMessage] Download failed: $e');
        if (mounted) {
          setState(() => _isDownloading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isClickable = _hasLocalFile || _canDownload;

    return GestureDetector(
      onTap: isClickable ? _handleTap : null,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(_getFileIcon(), size: 36, color: colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.fileSize != null)
                    Text(
                      _formatSize(widget.fileSize!),
                      style: TextStyle(
                        fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            _buildTrailingIcon(colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingIcon(ColorScheme colorScheme) {
    if (_isDownloading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          value: _downloadProgress > 0 ? _downloadProgress : null,
          strokeWidth: 2,
          color: colorScheme.primary,
        ),
      );
    }
    if (_hasLocalFile) {
      return const Icon(Icons.check_circle, size: 20, color: Colors.green);
    }
    if (_canDownload) {
      return Icon(
        Icons.download_rounded,
        size: 20,
        color: colorScheme.primary,
      );
    }
    return const SizedBox.shrink();
  }

  IconData _getFileIcon() {
    final ext = widget.fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf,
      'doc' || 'docx' => Icons.description,
      'xls' || 'xlsx' => Icons.table_chart,
      'zip' || 'rar' || '7z' => Icons.folder_zip,
      'mp3' || 'wav' || 'aac' => Icons.audio_file,
      'mp4' || 'mov' || 'avi' => Icons.video_file,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
