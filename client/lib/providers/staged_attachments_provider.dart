import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 暂存附件模型
class StagedAttachment {
  final String? path;
  final String type; // 'image' | 'file'
  final String? name;
  final int? size;
  final Uint8List? bytes; // 粘贴的图片（无文件路径时用）

  const StagedAttachment({
    this.path,
    required this.type,
    this.name,
    this.size,
    this.bytes,
  });

  bool get isImage => type == 'image';

  /// 判断文件扩展名是否为图片
  static bool isImagePath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic'}.contains(ext);
  }
}

/// 暂存附件列表 Provider
final stagedAttachmentsProvider =
    StateNotifierProvider<StagedAttachmentsNotifier, List<StagedAttachment>>(
      (ref) => StagedAttachmentsNotifier(),
    );

class StagedAttachmentsNotifier extends StateNotifier<List<StagedAttachment>> {
  StagedAttachmentsNotifier() : super([]);

  void add(StagedAttachment attachment) {
    state = [...state, attachment];
  }

  void addAll(List<StagedAttachment> attachments) {
    state = [...state, ...attachments];
  }

  void removeAt(int index) {
    final list = [...state];
    list.removeAt(index);
    state = list;
  }

  void clear() {
    state = [];
  }
}
