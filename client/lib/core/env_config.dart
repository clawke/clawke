/// 环境配置 —— 修改此文件切换环境。
class EnvConfig {
  EnvConfig._();

  /// clawke.ai Web 服务地址
  static const String webBaseUrl = 'https://clawke.ai';

  /// 桌面端 Google OAuth client id — Google OAuth client id for desktop platforms.
  static const String googleDesktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );

  /// 桌面端 Google OAuth client secret — Google OAuth client secret for desktop platforms.
  static const String googleDesktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  /// macOS App Store 包才启用 Apple 登录 — Enable Apple sign-in only for Mac App Store builds.
  static const bool macOSAppleSignInEnabled = bool.fromEnvironment(
    'CLAWKE_MACOS_APPLE_SIGN_IN_ENABLED',
    defaultValue: false,
  );

  /// macOS App Store 包禁用应用内更新 — Disable in-app updates for Mac App Store builds.
  static const bool macOSAppStoreBuild = bool.fromEnvironment(
    'CLAWKE_MACOS_APP_STORE_BUILD',
    defaultValue: false,
  );

  /// 是否允许自签名证书（本地开发时设为 true）
  static const bool allowBadCertificates = false;
}
