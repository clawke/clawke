import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 法律页面基础域名。
const _legalHost = 'https://clawke.ai';

/// 根据当前语言打开「服务条款」页面。
void openTermsOfService(BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  openUrl('$_legalHost/$lang/ai/legal/terms.htm');
}

/// 根据当前语言打开「隐私政策」页面。
void openPrivacyPolicy(BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  openUrl('$_legalHost/$lang/ai/legal/privacy.htm');
}

/// 统一打开外部链接。
///
/// - 移动端（iOS / Android）：应用内浏览器打开。
/// - 桌面端（macOS / Windows / Linux）：调用系统默认浏览器。
/// - 若首选模式失败，自动降级为外部浏览器。
Future<void> openUrl(String url) async {
  final uri = Uri.parse(url);
  final isMobile = Platform.isIOS || Platform.isAndroid;
  final mode = isMobile
      ? LaunchMode.inAppBrowserView
      : LaunchMode.externalApplication;

  try {
    if (!await launchUrl(uri, mode: mode)) {
      // 首选模式不可用，降级为外部浏览器
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    debugPrint('Failed to launch url: $e');
  }
}
