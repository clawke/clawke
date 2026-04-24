import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:client/models/message_model.dart';

/// 导航页面枚举
enum NavPage { chat, dashboard, tasks, cron, channels, skills }

/// 当前激活的页面
final activeNavPageProvider = StateProvider<NavPage>((ref) => NavPage.chat);

/// 每个工具页面缓存的 SDUI 数据（切换回来时保留）
final sduiPageCacheProvider = StateProvider<Map<NavPage, SduiMessage?>>(
  (ref) => {},
);
