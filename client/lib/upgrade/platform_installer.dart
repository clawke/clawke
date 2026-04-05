import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'upgrade_model.dart';

/// 按平台执行安装动作
class PlatformInstaller {
  /// 执行平台特定的安装/更新动作
  static Future<void> install(UpgradeInfo info) async {
    if (Platform.isIOS) {
      // 跳转 App Store
      await launchUrl(Uri.parse(info.downloadUrl));
    } else if (Platform.isAndroid) {
      // 优先跳应用市场
      if (info.marketPackage != null) {
        await _openMarket(info.marketPackage!);
      } else {
        // fallback: 打开浏览器下载 APK
        await launchUrl(Uri.parse(info.downloadUrl));
      }
    } else {
      // macOS / Windows / Linux → 打开浏览器下载
      await launchUrl(
        Uri.parse(info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  /// 尝试打开应用市场
  static Future<void> _openMarket(String packageName) async {
    // Android 应用市场 URI scheme
    final marketUri = Uri.parse('market://details?id=$packageName');
    if (await canLaunchUrl(marketUri)) {
      await launchUrl(marketUri);
    } else {
      // fallback: Google Play 网页
      await launchUrl(
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName'),
      );
    }
  }
}
