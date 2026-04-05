import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/data/database/app_database.dart';

/// 当前正在回复的消息（null = 不在回复状态）
final replyingToProvider = StateProvider<Message?>((ref) => null);

/// 当前正在编辑的消息（null = 不在编辑状态）
final editingMessageProvider = StateProvider<Message?>((ref) => null);
