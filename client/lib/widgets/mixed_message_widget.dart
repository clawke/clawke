import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:client/widgets/image_message_widget.dart';
import 'package:client/widgets/file_message_widget.dart';

class MixedMessageWidget extends StatelessWidget {
  final String content;
  final bool isUser;

  const MixedMessageWidget({
    super.key,
    required this.content,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(content) as Map);
    } catch (_) {
      return SelectableText(
        content,
        style: TextStyle(
          color: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
      );
    }

    final text = data['text'] as String? ?? '';
    final attachments = (data['attachments'] as List<dynamic>?) ?? [];

    // 分离图片和文件
    final images = attachments.where((a) => a['type'] == 'image').toList();
    final files = attachments.where((a) => a['type'] == 'file').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 图片区域
        if (images.isNotEmpty) _buildImageGrid(images),
        // 文件卡片
        for (final f in files) ...[
          if (images.isNotEmpty || files.indexOf(f) > 0)
            const SizedBox(height: 8),
          FileMessageWidget(
            fileName: f['name'] as String? ?? 'unknown',
            filePath: f['localPath'] as String?,
            mediaUrl: f['mediaUrl'] as String?,
            fileSize: f['size'] as int?,
          ),
        ],
        // 文字
        if (text.isNotEmpty) ...[
          if (images.isNotEmpty || files.isNotEmpty) const SizedBox(height: 8),
          SelectableText(
            text,
            style: TextStyle(
              color: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImageGrid(List<dynamic> images) {
    if (images.length == 1) {
      return _buildAttachmentImage(images[0]);
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: images.map((img) {
        return SizedBox(
          width: 120,
          height: 120,
          child: _buildAttachmentImage(img),
        );
      }).toList(),
    );
  }

  /// 从 attachment JSON 构建 ImageMessageWidget
  /// 支持新架构（mediaUrl/thumbUrl/thumbHash）和旧格式（path）
  Widget _buildAttachmentImage(dynamic att) {
    final map = att as Map<String, dynamic>? ?? {};
    return ImageMessageWidget(
      filePath: map['localPath'] as String?,
      mediaUrl: map['mediaUrl'] as String?,
      thumbUrl: map['thumbUrl'] as String?,
      thumbHash: map['thumbHash'] as String?,
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
    );
  }

}
