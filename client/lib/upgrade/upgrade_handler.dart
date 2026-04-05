import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'upgrade_model.dart';
import 'upgrade_dialog.dart';

/// 升级信息状态 — 当收到 update_available 时更新
final upgradeInfoProvider = StateProvider<UpgradeInfo?>((ref) => null);

/// 升级处理器：解析 system_status 消息，决定是否弹窗
class UpgradeHandler {
  /// 处理 system_status 消息
  ///
  /// 如果 status == 'update_available'，解析升级信息并弹窗。
  /// 返回 true 如果是升级相关消息（已处理），false 表示不是升级消息。
  static bool handleSystemStatus(
    Map<String, dynamic> msg,
    WidgetRef ref,
    BuildContext context,
  ) {
    final status = msg['status'] as String?;
    if (status != 'update_available') return false;

    final info = UpgradeInfo.fromSystemStatus(msg);
    if (!info.isAvailable) return false;

    // 保存到 provider
    ref.read(upgradeInfoProvider.notifier).state = info;

    // 弹窗
    UpgradeDialog.show(context, info);
    return true;
  }

  /// 从 Ref 处理（非 Widget 上下文，如 WsMessageHandler）
  static bool handleSystemStatusFromRef(Map<String, dynamic> msg, Ref ref) {
    final status = msg['status'] as String?;
    if (status != 'update_available') return false;

    final info = UpgradeInfo.fromSystemStatus(msg);
    if (!info.isAvailable) return false;

    // 保存到 provider（UI 层响应 provider 变化来弹窗）
    ref.read(upgradeInfoProvider.notifier).state = info;
    return true;
  }
}
