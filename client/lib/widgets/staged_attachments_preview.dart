import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:client/providers/staged_attachments_provider.dart';

class StagedAttachmentsPreview extends ConsumerWidget {
  const StagedAttachmentsPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(stagedAttachmentsProvider);
    if (attachments.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final att = attachments[index];
            return att.isImage
                ? _ImagePreview(attachment: att, index: index)
                : _FilePreview(attachment: att, index: index);
          },
        ),
      ),
    );
  }
}

class _ImagePreview extends ConsumerWidget {
  final StagedAttachment attachment;
  final int index;

  const _ImagePreview({required this.attachment, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: attachment.path != null
          ? () => OpenFilex.open(attachment.path!)
          : null,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 64,
              height: 64,
              child: _buildImage(colorScheme),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: _RemoveButton(
              onTap: () =>
                  ref.read(stagedAttachmentsProvider.notifier).removeAt(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(ColorScheme colorScheme) {
    if (attachment.bytes != null) {
      return Image.memory(attachment.bytes!, fit: BoxFit.cover);
    }
    if (attachment.path != null) {
      return Image.file(File(attachment.path!), fit: BoxFit.cover);
    }
    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Icon(Icons.image, color: colorScheme.onSurfaceVariant),
    );
  }
}

class _FilePreview extends ConsumerWidget {
  final StagedAttachment attachment;
  final int index;

  const _FilePreview({required this.attachment, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: attachment.path != null
          ? () => OpenFilex.open(attachment.path!)
          : null,
      child: Stack(
        children: [
          Container(
            width: 140,
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(_getFileIcon(), size: 28, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.name ?? 'file',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: Theme.of(context).textTheme.labelMedium!.fontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (attachment.size != null)
                        Text(
                          _formatSize(attachment.size!),
                          style: TextStyle(
                            fontSize: Theme.of(context).textTheme.labelSmall!.fontSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: _RemoveButton(
              onTap: () =>
                  ref.read(stagedAttachmentsProvider.notifier).removeAt(index),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final ext = (attachment.name ?? '').split('.').last.toLowerCase();
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

class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, size: 14, color: Colors.white),
      ),
    );
  }
}
